using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace WindowsUpdateAnalytics;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        try
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
        catch (Exception ex)
        {
            var logPath = StartupFailureLog.TryWrite(ex);
            var detail = string.IsNullOrWhiteSpace(logPath)
                ? ex.ToString()
                : $"{ex}\n\nStartup details were saved to:\n{logPath}";
            MessageBox.Show(detail, "Windows Update Analytics could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

internal sealed class MainForm : Form
{
    private const string AppVersion = "2.2.0";
    private readonly Label _status = new();
    private readonly Label _statusDetail = new();
    private readonly TextBox _outputPath = new();
    private readonly TextBox _copyTo = new();
    private readonly TextBox _mediaPath = new();
    private readonly ComboBox _target = new();
    private readonly NumericUpDown _armDays = new();
    private readonly CheckBox _acceptEula = new();
    private readonly CheckBox _largeDumps = new();
    private readonly CheckBox _noInternet = new();
    private readonly CheckBox _noHooks = new();
    private readonly TextBox _log = new();
    private readonly Button _start = new();
    private readonly Button _finalize = new();
    private readonly Button _forensic = new();
    private readonly Button _disarm = new();
    private readonly Button _openReport = new();
    private readonly Button _openEvidence = new();
    private readonly System.Windows.Forms.Timer _stateTimer = new();
    private bool _busy;
    private string? _runtimePath;
    private string? _lastOutputPath;
    private DateTime _actionStartedUtc;

    public MainForm()
    {
        Text = $"Windows Update Analytics {AppVersion}";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(920, 720);
        Size = new Size(1040, 800);
        BackColor = Color.FromArgb(245, 247, 250);
        Font = new Font("Segoe UI", 9F);
        BuildInterface();
        Load += OnLoaded;
        FormClosing += OnClosing;
    }

    private void BuildInterface()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(20),
            RowCount = 5,
            ColumnCount = 1,
            AutoScroll = true
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        var heading = new Panel { Dock = DockStyle.Top, Height = 74, BackColor = Color.FromArgb(18, 43, 70), Padding = new Padding(18, 12, 18, 8) };
        heading.Controls.Add(new Label
        {
            Text = "Windows Update Analytics",
            ForeColor = Color.White,
            Font = new Font("Segoe UI Semibold", 18F),
            Dock = DockStyle.Top,
            AutoSize = true
        });
        heading.Controls.Add(new Label
        {
            Text = "Persistent Windows 11 feature-update evidence recorder",
            ForeColor = Color.FromArgb(194, 216, 238),
            Dock = DockStyle.Bottom,
            AutoSize = true
        });
        root.Controls.Add(heading);

        var statusPanel = new Panel { Dock = DockStyle.Top, Height = 78, BackColor = Color.White, Padding = new Padding(16), Margin = new Padding(0, 12, 0, 12) };
        _status.Text = "Loading status…";
        _status.Font = new Font("Segoe UI Semibold", 13F);
        _status.ForeColor = Color.FromArgb(18, 43, 70);
        _status.Dock = DockStyle.Top;
        _status.AutoSize = true;
        _statusDetail.Text = "Inspecting the durable case state.";
        _statusDetail.ForeColor = Color.FromArgb(75, 85, 99);
        _statusDetail.Dock = DockStyle.Bottom;
        _statusDetail.AutoEllipsis = true;
        statusPanel.Controls.Add(_statusDetail);
        statusPanel.Controls.Add(_status);
        root.Controls.Add(statusPanel);

        var actionPanel = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Margin = new Padding(0, 0, 0, 12) };
        ConfigureAction(_start, "Start monitoring", Color.FromArgb(0, 102, 204), async (_, _) => await RunModeAsync("Preflight"));
        ConfigureAction(_finalize, "Finalize and build report", Color.FromArgb(0, 122, 102), (_, _) => FinalizeOrCopyAsync());
        ConfigureAction(_forensic, "One-time forensic report", Color.FromArgb(88, 80, 141), async (_, _) => await RunModeAsync("Forensic"));
        ConfigureAction(_disarm, "Stop monitoring", Color.FromArgb(160, 72, 40), (_, _) => ConfirmDisarmAsync());
        ConfigureAction(_openReport, "Open latest report", Color.FromArgb(70, 82, 95), (_, _) => OpenLatestReport());
        ConfigureAction(_openEvidence, "Open case folder", Color.FromArgb(70, 82, 95), (_, _) => OpenCaseFolder());
        actionPanel.Controls.AddRange(new Control[] { _start, _finalize, _forensic, _disarm, _openReport, _openEvidence });
        root.Controls.Add(actionPanel);

        // SplitterDistance and panel minimums cannot be assigned safely until
        // WinForms has calculated the DPI-scaled client height. Assigning them
        // in the initializer can terminate startup on a freshly laid-out form.
        var middle = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal };
        Shown += (_, _) => ConfigureSplitter(middle);
        middle.Panel1.Controls.Add(BuildSettingsPanel());
        _log.Dock = DockStyle.Fill;
        _log.Multiline = true;
        _log.ReadOnly = true;
        _log.ScrollBars = ScrollBars.Both;
        _log.WordWrap = false;
        _log.Font = new Font("Consolas", 8.5F);
        _log.BackColor = Color.FromArgb(20, 25, 31);
        _log.ForeColor = Color.FromArgb(220, 230, 238);
        middle.Panel2.Controls.Add(_log);
        root.Controls.Add(middle);

        var footer = new Label
        {
            Text = "Preflight arms monitoring but does not publish a report. Reports are created only after automatic completion, Finalize, or Forensic collection.",
            AutoSize = true,
            ForeColor = Color.FromArgb(75, 85, 99),
            Padding = new Padding(0, 8, 0, 0)
        };
        root.Controls.Add(footer);
    }

    private static void ConfigureSplitter(SplitContainer middle)
    {
        var available = middle.ClientSize.Height - middle.SplitterWidth;
        if (available < 300) return;
        middle.Panel1MinSize = 160;
        middle.Panel2MinSize = 120;
        middle.SplitterDistance = Math.Clamp(238, middle.Panel1MinSize, available - middle.Panel2MinSize);
    }

    private Control BuildSettingsPanel()
    {
        var group = new GroupBox { Text = "Collection settings", Dock = DockStyle.Fill, Padding = new Padding(12) };
        var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 5 };
        for (var row = 0; row < grid.RowCount; row++) grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));

        _target.DropDownStyle = ComboBoxStyle.DropDownList;
        _target.Items.Add("25H2");
        _target.SelectedIndex = 0;
        _armDays.Minimum = 1;
        _armDays.Maximum = 365;
        _armDays.Value = 30;
        AddSetting(grid, 0, "Target", _target, "Keep monitoring (days)", _armDays);

        _outputPath.Text = GetPublicDocuments();
        var outputPicker = BuildPathPicker(_outputPath, false);
        AddSetting(grid, 1, "Final report parent", outputPicker, "Optional UNC copy", _copyTo);

        var mediaPicker = BuildPathPicker(_mediaPath, false);
        _acceptEula.Text = "Accept Windows EULA for media scan";
        _acceptEula.AutoSize = true;
        AddSetting(grid, 2, "Optional 25H2 media", mediaPicker, "Media scan", _acceptEula);

        _largeDumps.Text = "Include full MEMORY.DMP when capacity permits";
        _noInternet.Text = "Do not test public endpoints or download SetupDiag";
        _noHooks.Text = "Do not add SetupConfig outcome hooks";
        foreach (var box in new[] { _largeDumps, _noInternet, _noHooks }) box.AutoSize = true;
        grid.Controls.Add(_largeDumps, 0, 3);
        grid.SetColumnSpan(_largeDumps, 2);
        grid.Controls.Add(_noInternet, 2, 3);
        grid.SetColumnSpan(_noInternet, 2);
        grid.Controls.Add(_noHooks, 0, 4);
        grid.SetColumnSpan(_noHooks, 2);

        group.Controls.Add(grid);
        return group;
    }

    private static void AddSetting(TableLayoutPanel grid, int row, string leftLabel, Control left, string rightLabel, Control right)
    {
        var first = new Label { Text = leftLabel, AutoSize = true, Anchor = AnchorStyles.Left, Padding = new Padding(0, 5, 8, 0) };
        var second = new Label { Text = rightLabel, AutoSize = true, Anchor = AnchorStyles.Left, Padding = new Padding(18, 5, 8, 0) };
        left.Dock = DockStyle.Fill;
        right.Dock = DockStyle.Fill;
        grid.Controls.Add(first, 0, row);
        grid.Controls.Add(left, 1, row);
        grid.Controls.Add(second, 2, row);
        grid.Controls.Add(right, 3, row);
    }

    private static Control BuildPathPicker(TextBox textBox, bool filesOnly)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 2, RowCount = 1, Margin = new Padding(0) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        textBox.Dock = DockStyle.Fill;
        var browse = new Button { Text = "…", Width = 34, Height = 25, Margin = new Padding(4, 0, 0, 0) };
        browse.Click += (_, _) =>
        {
            using var picker = new FolderBrowserDialog { ShowNewFolderButton = !filesOnly };
            if (Directory.Exists(textBox.Text)) picker.SelectedPath = textBox.Text;
            if (picker.ShowDialog() == DialogResult.OK) textBox.Text = picker.SelectedPath;
        };
        panel.Controls.Add(textBox, 0, 0);
        panel.Controls.Add(browse, 1, 0);
        return panel;
    }

    private static void ConfigureAction(Button button, string text, Color color, EventHandler click)
    {
        button.Text = text;
        button.AutoSize = true;
        button.Height = 34;
        button.Padding = new Padding(10, 0, 10, 0);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.BackColor = color;
        button.ForeColor = Color.White;
        button.Margin = new Padding(0, 0, 8, 8);
        button.Click += click;
    }

    private async void OnLoaded(object? sender, EventArgs e)
    {
        try
        {
            AppendLog("Preparing the verified embedded diagnostic engine…");
            _runtimePath = await Task.Run(() => PayloadManager.EnsureExtracted(AppVersion));
            AppendLog($"Runtime ready: {_runtimePath}");
            RefreshState();
            _stateTimer.Interval = 5000;
            _stateTimer.Tick += (_, _) => { if (!_busy) RefreshState(); };
            _stateTimer.Start();
        }
        catch (Exception ex)
        {
            SetStatus("Application could not start", ex.Message, true);
            AppendLog(ex.ToString());
            MessageBox.Show(this, ex.Message, "Windows Update Analytics", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async void ConfirmFinalizeAsync()
    {
        var answer = MessageBox.Show(this,
            "Finalize stops persistent monitoring, takes one final checkpoint, builds the report, and removes this case's tasks and hooks. Continue?",
            "Finalize monitored case", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer == DialogResult.Yes) await RunModeAsync("Finalize");
    }

    private async void FinalizeOrCopyAsync()
    {
        var active = ActiveRunInfo.TryRead();
        if (active?.Status.Equals("AwaitingInteractiveCopy", StringComparison.OrdinalIgnoreCase) == true)
        {
            await RunModeAsync("Resume");
            return;
        }
        ConfirmFinalizeAsync();
    }

    private async void ConfirmDisarmAsync()
    {
        var answer = MessageBox.Show(this,
            "Stop monitoring removes this case's scheduled tasks and hooks but does not create a report. Existing evidence remains in ProgramData. Continue?",
            "Stop monitoring", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer == DialogResult.Yes) await RunModeAsync("Disarm");
    }

    private async Task RunModeAsync(string mode)
    {
        if (_busy || string.IsNullOrWhiteSpace(_runtimePath)) return;
        if (!ValidateSettings(mode)) return;

        _busy = true;
        _actionStartedUtc = DateTime.UtcNow;
        SetBusyState(true);
        _log.Clear();
        SetStatus($"{ModeTitle(mode)} is running", "Keep this window open. Detailed progress appears below.", false);
        AppendLog($"Starting {mode} at {_actionStartedUtc:O}");

        var activeBefore = ActiveRunInfo.TryRead();
        if (activeBefore?.OutputPath is { Length: > 0 }) _lastOutputPath = activeBefore.OutputPath;
        try
        {
            var exitCode = await RunBackendAsync(mode);
            RefreshState();
            var activeAfter = ActiveRunInfo.TryRead();
            if (activeAfter?.OutputPath is { Length: > 0 }) _lastOutputPath = activeAfter.OutputPath;

            if (mode == "Preflight")
            {
                if (activeAfter is not null && activeAfter.Status.StartsWith("Armed", StringComparison.OrdinalIgnoreCase))
                {
                    var recorderVerified = activeAfter.RecorderStartStatus.Equals("Started", StringComparison.OrdinalIgnoreCase);
                    SetStatus(recorderVerified ? "Monitoring is armed" : "Recorder startup was not verified",
                        recorderVerified
                            ? $"Run {activeAfter.RunId} is recording. No final report has been created. Armed until {activeAfter.ExpiresUtcLocal}."
                            : $"Run {activeAfter.RunId} was staged, but the persistent recorder returned '{activeAfter.RecorderStartStatus}'. Review the progress log before starting the upgrade.",
                        !recorderVerified || exitCode != 0);
                    MessageBox.Show(this,
                        recorderVerified
                            ? $"Monitoring is armed for run {activeAfter.RunId}.\n\nNo report was created because the upgrade has not finished. The final report will be built automatically after a terminal outcome, or when you select Finalize and build report.\n\nExit code: {exitCode}"
                            : $"The case was staged, but persistent recorder startup was not verified.\n\nRecorder status: {activeAfter.RecorderStartStatus}\nExit code: {exitCode}\n\nDo not treat this as a healthy monitored case until the recorded error is resolved.",
                        "Preflight complete", MessageBoxButtons.OK, exitCode == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                }
                else
                {
                    throw new InvalidOperationException($"Preflight exited with code {exitCode}, but no armed run state could be verified.");
                }
            }
            else if (mode is "Finalize" or "Forensic" or "Resume")
            {
                var report = FindLatestReport();
                SetStatus(exitCode is 0 or 10 or 20 ? "Report created" : "Collection finished with limitations",
                    report ?? $"Backend exit code: {exitCode}", exitCode >= 30);
                if (report is not null)
                {
                    _lastOutputPath = Path.GetDirectoryName(report);
                    var answer = MessageBox.Show(this, $"Report collection finished with exit code {exitCode}.\n\nOpen the report now?", "Report ready", MessageBoxButtons.YesNo, exitCode >= 30 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
                    if (answer == DialogResult.Yes) OpenPath(report);
                }
            }
            else if (mode == "Disarm")
            {
                SetStatus("Monitoring stopped", "Owned tasks and hooks were removed. Existing evidence was retained; no report was created.", exitCode != 0);
            }
        }
        catch (Exception ex)
        {
            SetStatus($"{ModeTitle(mode)} failed", ex.Message, true);
            AppendLog(ex.ToString());
            MessageBox.Show(this, ex.Message, "Windows Update Analytics", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _busy = false;
            SetBusyState(false);
            RefreshState(false);
        }
    }

    private bool ValidateSettings(string mode)
    {
        if (mode is "Finalize" or "Disarm") return true;
        if (string.IsNullOrWhiteSpace(_outputPath.Text) || _outputPath.Text.StartsWith("\\\\", StringComparison.Ordinal))
        {
            MessageBox.Show(this, "The final report parent must be a local folder. Use Optional UNC copy for a network destination.", "Invalid output folder", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        if (!string.IsNullOrWhiteSpace(_copyTo.Text) && !_copyTo.Text.StartsWith("\\\\", StringComparison.Ordinal))
        {
            MessageBox.Show(this, "The optional copy destination must be a UNC path such as \\\\server\\share\\WindowsUpdateAnalytics.", "Invalid UNC path", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        if (!string.IsNullOrWhiteSpace(_mediaPath.Text) && !_acceptEula.Checked)
        {
            MessageBox.Show(this, "Select EULA acceptance before requesting a media compatibility scan.", "EULA acceptance required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        return true;
    }

    private async Task<int> RunBackendAsync(string mode)
    {
        var systemRoot = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
        var powerShell = Path.Combine(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powerShell)) throw new FileNotFoundException("64-bit Windows PowerShell was not found.", powerShell);
        var script = Path.Combine(_runtimePath!, "Invoke-Win11UpgradeDiag.ps1");
        var publicDocuments = GetPublicDocuments();
        Directory.CreateDirectory(publicDocuments);
        var bootstrapLog = Path.Combine(publicDocuments, "Win11UpgradeDiag-Launcher.log");
        var startInfo = new ProcessStartInfo
        {
            FileName = powerShell,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = _runtimePath!
        };
        foreach (var argument in BuildArguments(mode, script, bootstrapLog)) startInfo.ArgumentList.Add(argument);

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, args) => { if (args.Data is not null) AppendLog(args.Data); };
        process.ErrorDataReceived += (_, args) => { if (args.Data is not null) AppendLog("ERROR: " + args.Data); };
        if (!process.Start()) throw new InvalidOperationException("Windows PowerShell did not start.");
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();
        AppendLog($"Backend exited with code {process.ExitCode}.");
        return process.ExitCode;
    }

    private IEnumerable<string> BuildArguments(string mode, string script, string bootstrapLog)
    {
        var values = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Mode", mode, "-NoOpen", "-BootstrapLogPath", bootstrapLog };
        if (mode is "Preflight" or "Forensic")
        {
            values.AddRange(new[] { "-TargetVersion", _target.Text, "-OutputPath", Path.GetFullPath(_outputPath.Text), "-ArmDays", ((int)_armDays.Value).ToString() });
            if (!string.IsNullOrWhiteSpace(_copyTo.Text)) values.AddRange(new[] { "-CopyTo", _copyTo.Text.Trim() });
            if (!string.IsNullOrWhiteSpace(_mediaPath.Text))
            {
                values.AddRange(new[] { "-MediaPath", _mediaPath.Text.Trim(), "-AcceptWindowsEula" });
            }
            if (_largeDumps.Checked) values.Add("-IncludeLargeDumps");
            if (_noInternet.Checked) values.Add("-NoInternet");
            if (_noHooks.Checked) values.Add("-NoSetupHooks");
        }
        return values;
    }

    private void RefreshState(bool setStatus = true)
    {
        var active = ActiveRunInfo.TryRead();
        if (active is not null)
        {
            _lastOutputPath = active.OutputPath;
            var copyPending = active.Status.Equals("AwaitingInteractiveCopy", StringComparison.OrdinalIgnoreCase);
            var recorderFailed = !string.IsNullOrWhiteSpace(active.RecorderStartStatus) && !active.RecorderStartStatus.Equals("Started", StringComparison.OrdinalIgnoreCase);
            if (setStatus && !_busy)
            {
                if (copyPending) SetStatus("Final report ready; network copy is pending", $"Run {active.RunId} retained its state so an interactive technician can complete the requested UNC copy.", true);
                else if (recorderFailed) SetStatus("Monitoring needs attention", $"Run {active.RunId} recorder startup status: {active.RecorderStartStatus}.", true);
                else SetStatus("Monitoring is armed", $"Run {active.RunId} • target {active.TargetVersion} • expires {active.ExpiresUtcLocal}", false);
            }
            _start.Enabled = false;
            _forensic.Enabled = false;
            _finalize.Enabled = !_busy;
            _finalize.Text = copyPending ? "Complete pending network copy" : "Finalize and build report";
            _disarm.Enabled = !_busy;
            _openEvidence.Enabled = Directory.Exists(active.RunPath);
            _openReport.Enabled = File.Exists(Path.Combine(active.OutputPath ?? string.Empty, "Report.html")) || FindLatestReport() is not null;
        }
        else
        {
            _finalize.Text = "Finalize and build report";
            if (setStatus && !_busy) SetStatus("No monitored upgrade is active", "Choose Start monitoring before Windows Update offers or installs 25H2, or create a one-time forensic report.", false);
            _start.Enabled = !_busy;
            _forensic.Enabled = !_busy;
            _finalize.Enabled = false;
            _disarm.Enabled = false;
            _openEvidence.Enabled = false;
            _openReport.Enabled = FindLatestReport() is not null;
        }
    }

    private void SetBusyState(bool busy)
    {
        UseWaitCursor = busy;
        _start.Enabled = !busy;
        _finalize.Enabled = !busy;
        _forensic.Enabled = !busy;
        _disarm.Enabled = !busy;
        _openReport.Enabled = !busy;
        _openEvidence.Enabled = !busy;
        foreach (var control in new Control[] { _outputPath, _copyTo, _mediaPath, _target, _armDays, _acceptEula, _largeDumps, _noInternet, _noHooks }) control.Enabled = !busy;
    }

    private void SetStatus(string title, string detail, bool warning)
    {
        if (InvokeRequired) { BeginInvoke(new Action(() => SetStatus(title, detail, warning))); return; }
        _status.Text = title;
        _status.ForeColor = warning ? Color.FromArgb(170, 65, 45) : Color.FromArgb(18, 43, 70);
        _statusDetail.Text = detail;
    }

    private void AppendLog(string text)
    {
        if (InvokeRequired) { BeginInvoke(new Action(() => AppendLog(text))); return; }
        _log.AppendText(text + Environment.NewLine);
        _log.SelectionStart = _log.TextLength;
        _log.ScrollToCaret();
    }

    private void OpenLatestReport()
    {
        var report = FindLatestReport();
        if (report is null) MessageBox.Show(this, "No finalized report was found. An armed Preflight does not create one.", "No report yet", MessageBoxButtons.OK, MessageBoxIcon.Information);
        else OpenPath(report);
    }

    private void OpenCaseFolder()
    {
        var active = ActiveRunInfo.TryRead();
        var path = active?.RunPath;
        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path)) OpenPath(path);
    }

    private string? FindLatestReport()
    {
        if (!string.IsNullOrWhiteSpace(_lastOutputPath))
        {
            var known = Path.Combine(_lastOutputPath, "Report.html");
            if (File.Exists(known)) return known;
        }
        var parent = _outputPath.Text;
        if (!Directory.Exists(parent)) return null;
        try
        {
            return Directory.EnumerateFiles(parent, "Report.html", SearchOption.AllDirectories)
                .Select(path => new FileInfo(path))
                .Where(file => file.Directory?.Name.StartsWith("Win11UpgradeDiag-", StringComparison.OrdinalIgnoreCase) == true)
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .FirstOrDefault()?.FullName;
        }
        catch { return null; }
    }

    private static void OpenPath(string path) => Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });

    private static string ModeTitle(string mode) => mode switch
    {
        "Preflight" => "Preflight baseline",
        "Finalize" => "Final collection",
        "Resume" => "Deferred network copy",
        "Forensic" => "Forensic collection",
        "Disarm" => "Monitoring cleanup",
        _ => mode
    };

    private static string GetPublicDocuments()
    {
        var publicRoot = Environment.GetEnvironmentVariable("PUBLIC");
        if (!string.IsNullOrWhiteSpace(publicRoot)) return Path.Combine(publicRoot, "Documents");
        return Environment.GetFolderPath(Environment.SpecialFolder.CommonDocuments);
    }

    private void OnClosing(object? sender, FormClosingEventArgs e)
    {
        if (!_busy) return;
        e.Cancel = true;
        MessageBox.Show(this, "A collection is still running. Wait for it to finish before closing the application so its final status can be verified.", "Collection in progress", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
}

internal static class StartupFailureLog
{
    public static string? TryWrite(Exception exception)
    {
        try
        {
            var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var directory = Path.Combine(programData, "WindowsUpdateAnalytics");
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "Gui-Startup-Failure.log");
            File.AppendAllText(path, $"[{DateTime.UtcNow:O}] Windows Update Analytics GUI startup failure{Environment.NewLine}{exception}{Environment.NewLine}{Environment.NewLine}", Encoding.UTF8);
            return path;
        }
        catch
        {
            return null;
        }
    }
}

internal sealed class ActiveRunInfo
{
    public string RunId { get; private init; } = string.Empty;
    public string Status { get; private init; } = string.Empty;
    public string TargetVersion { get; private init; } = string.Empty;
    public string RunPath { get; private init; } = string.Empty;
    public string? OutputPath { get; private init; }
    public string RecorderStartStatus { get; private init; } = string.Empty;
    public DateTime? ExpiresUtc { get; private init; }
    public string ExpiresUtcLocal => ExpiresUtc?.ToLocalTime().ToString("g") ?? "unknown";

    public static ActiveRunInfo? TryRead()
    {
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var path = Path.Combine(programData, "Win11UpgradeDiag", "ActiveRun.json");
        if (!File.Exists(path)) return null;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            var recorderStartStatus = string.Empty;
            if (root.TryGetProperty("RecorderStart", out var recorderStart) && recorderStart.ValueKind == JsonValueKind.Object && recorderStart.TryGetProperty("Status", out var recorderStatus))
                recorderStartStatus = recorderStatus.ToString();
            return new ActiveRunInfo
            {
                RunId = ReadString(root, "RunId"),
                Status = ReadString(root, "Status"),
                TargetVersion = ReadString(root, "TargetVersion"),
                RunPath = ReadString(root, "RunPath"),
                OutputPath = ReadString(root, "OutputPath"),
                RecorderStartStatus = recorderStartStatus,
                ExpiresUtc = DateTime.TryParse(ReadString(root, "ExpiresUtc"), out var expires) ? expires.ToUniversalTime() : null
            };
        }
        catch { return null; }
    }

    private static string ReadString(JsonElement root, string name) => root.TryGetProperty(name, out var value) ? value.ToString() : string.Empty;
}

internal static class PayloadManager
{
    private const string ResourcePrefix = "Payload/";

    public static string EnsureExtracted(string version)
    {
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var parent = Path.Combine(programData, "WindowsUpdateAnalytics", "Runtime");
        var destination = Path.Combine(parent, version);
        Directory.CreateDirectory(parent);
        if (Directory.Exists(destination))
        {
            try
            {
                VerifyEmbeddedManifestMatches(destination);
                VerifyManifest(destination);
                return destination;
            }
            catch
            {
                var quarantine = destination + ".invalid-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssZ");
                Directory.Move(destination, quarantine);
            }
        }

        var staging = Path.Combine(parent, ".extract-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var resources = assembly.GetManifestResourceNames().Where(name => name.StartsWith(ResourcePrefix, StringComparison.Ordinal)).ToArray();
            if (resources.Length == 0) throw new InvalidOperationException("The executable contains no diagnostic payload.");
            var stagingPrefix = Path.GetFullPath(staging) + Path.DirectorySeparatorChar;
            foreach (var resource in resources)
            {
                var relative = resource[ResourcePrefix.Length..].Replace('/', Path.DirectorySeparatorChar);
                var target = Path.GetFullPath(Path.Combine(staging, relative));
                if (!target.StartsWith(stagingPrefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("An embedded payload path left the extraction root.");
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var input = assembly.GetManifestResourceStream(resource) ?? throw new InvalidOperationException($"Embedded resource was unreadable: {resource}");
                using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                input.CopyTo(output);
            }
            VerifyManifest(staging);
            Directory.Move(staging, destination);
            return destination;
        }
        catch
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            throw;
        }
    }

    private static void VerifyEmbeddedManifestMatches(string root)
    {
        var installed = Path.Combine(root, "BundleManifest.sha256");
        var assembly = Assembly.GetExecutingAssembly();
        using var expectedStream = assembly.GetManifestResourceStream(ResourcePrefix + "BundleManifest.sha256")
            ?? throw new InvalidOperationException("The executable's embedded bundle manifest is missing.");
        using var expectedHash = SHA256.Create();
        var expected = expectedHash.ComputeHash(expectedStream);
        using var actualStream = File.OpenRead(installed);
        using var actualHash = SHA256.Create();
        var actual = actualHash.ComputeHash(actualStream);
        if (!CryptographicOperations.FixedTimeEquals(expected, actual))
            throw new InvalidOperationException("The installed runtime belongs to a different build of this version.");
    }

    private static void VerifyManifest(string root)
    {
        var manifest = Path.Combine(root, "BundleManifest.sha256");
        if (!File.Exists(manifest)) throw new InvalidOperationException("The embedded bundle manifest is missing.");
        var rootPrefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        var verified = 0;
        foreach (var line in File.ReadLines(manifest))
        {
            if (string.IsNullOrWhiteSpace(line) || line.TrimStart().StartsWith('#')) continue;
            var match = Regex.Match(line, "^([A-Fa-f0-9]{64})\\s+\\*?(.+)$");
            if (!match.Success) throw new InvalidOperationException("The embedded bundle manifest is malformed.");
            var relative = match.Groups[2].Value.Trim().Replace('/', Path.DirectorySeparatorChar);
            var candidate = Path.GetFullPath(Path.Combine(root, relative));
            if (!candidate.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) || !File.Exists(candidate)) throw new InvalidOperationException($"Embedded payload file is missing or unsafe: {relative}");
            using var stream = File.OpenRead(candidate);
            var actual = Convert.ToHexString(SHA256.HashData(stream));
            if (!actual.Equals(match.Groups[1].Value, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException($"Embedded payload integrity check failed: {relative}");
            verified++;
        }
        if (verified == 0) throw new InvalidOperationException("The embedded bundle manifest contains no file records.");
    }
}
