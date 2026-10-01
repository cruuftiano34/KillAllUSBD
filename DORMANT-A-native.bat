<# : DORMANT
@echo off
setlocal
set "DORMANT_SELF=%~f0"
fltmc >nul 2>&1 || (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:DORMANT_SELF -Verb RunAs } catch { }"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:DORMANT_SELF))"
exit /b

   ____    ___   ____   __  __     _     _   _  _____
  |  _ \  / _ \ |  _ \ |  \/  |   / \   | \ | ||_   _|
  | | | || | | || |_) || |\/| |  / _ \  |  \| |  | |
  | |_| || |_| ||  _ < | |  | | / ___ \ | |\  |  | |
  |____/  \___/ |_| \_\|_|  |_|/_/   \_\|_| \_|  |_|

  DORMANT  //  power schedule + idle loop system
  v3.0.0   //  made by Marcelo Torres
  target   //  Windows 10 / 11
  usage    //  copy to a USB drive, double-click, choose a video
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Version        = '3.2.0  (A / native player)'
$script:Author         = 'Marcelo Torres'
$script:Root           = Join-Path $env:ProgramData 'DORMANT'
$script:ExePath        = Join-Path $script:Root 'DORMANT.exe'
$script:PagePath       = Join-Path $script:Root 'loop.html'
$script:TaskPath       = '\DORMANT\'
$script:PowerCfg       = Join-Path $env:WINDIR 'System32\powercfg.exe'
$script:CacheDir       = Join-Path (Split-Path -Parent $env:DORMANT_SELF) 'DORMANT-cache'
$script:Weekdays       = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
$script:WakeWeek       = '10:00'
$script:WakeSunday     = '12:00'
$script:SleepWeek      = '18:00'
$script:SleepSunday    = '17:00'
$script:Formats        = @('.mp4', '.m4v', '.mov', '.webm')
$script:WebView2Id     = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$script:WebView2Setup  = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$script:WebView2SdkVer = '1.0.1518.46'
$script:WebView2Sdk    = 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.1518.46'
$script:SdkFiles       = @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')
$script:LoaderFlavors  = @('x64', 'x86', 'arm64')
$script:LogoPaths      = @('AgLogo\AgLogo.png', 'AgLogo.png', 'Dormant\AgLogo\AgLogo.png', 'AgLogo\AgLogo.jpg', 'AgLogo.jpg')
$script:WallPaths      = @('Walllpapers\AgWallpaper.png', 'Wallpapers\AgWallpaper.png', 'AgWallpaper.png', 'Walllpapers\AgWallpaper.jpg', 'Wallpapers\AgWallpaper.jpg', 'AgWallpaper.jpg', 'Walllpapers\AgWallpaper.jpeg', 'Wallpapers\AgWallpaper.jpeg')
$script:WidePaths      = @('Walllpapers\AgWallpaperUltraw.png', 'Wallpapers\AgWallpaperUltraw.png', 'AgWallpaperUltraw.png', 'Walllpapers\AgWallpaperUltraw.jpg', 'Wallpapers\AgWallpaperUltraw.jpg', 'AgWallpaperUltraw.jpg')
$script:CachePaths     = @('DORMANT-cache\webview2-sdk.nupkg', 'DORMANT\DORMANT-cache\webview2-sdk.nupkg', 'Dormant\DORMANT-cache\webview2-sdk.nupkg')
$script:WebDirs        = @('Web', 'Dormant\Web')
$script:NightFlag      = Join-Path $script:Root 'night.flag'
$script:HelperPath     = Join-Path $script:Root 'night.cmd'
$script:ModeFile       = Join-Path $script:Root 'power-mode.txt'
$script:Uninstaller    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Uninstall DORMANT.bat'
$script:UninstallMode  = [System.IO.Path]::GetFileName($env:DORMANT_SELF) -like 'Uninstall*'
$script:Failures       = 0

$script:PlayerSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Dormant
{
    internal static class ExitCodes
    {
        public const int Ok = 0;
        public const int InitFailed = 10;
        public const int NavigationFailed = 11;
        public const int VideoFailed = 12;
        public const int TimedOut = 13;
        public const int MissingPage = 14;
        public const int Crashed = 15;
    }

    public static class Program
    {
        private static Mutex gate;
        public static string TestResultPath;

        [STAThread]
        public static int Main(string[] args)
        {
            int testIndex = args == null ? -1 : Array.IndexOf(args, "--test");
            bool testMode = testIndex >= 0;
            if (testMode && testIndex + 1 < args.Length)
            {
                TestResultPath = args[testIndex + 1];
            }
            AppDomain.CurrentDomain.UnhandledException += OnDomainException;
            try
            {
                return Run(testMode);
            }
            catch (Exception error)
            {
                ReportTest(Describe(error));
                return ExitCodes.Crashed;
            }
        }

        private static int Run(bool testMode)
        {
            string baseFolder = AppDomain.CurrentDomain.BaseDirectory;
            if (LoopController.FirstVideo(baseFolder) == null)
            {
                ReportTest("no video file was found next to the player");
                return testMode ? ExitCodes.MissingPage : ExitCodes.Ok;
            }

            if (!testMode)
            {
                bool createdNew;
                gate = new Mutex(true, "Local\\Dormant.Loop", out createdNew);
                if (!createdNew)
                {
                    gate.Dispose();
                    gate = null;
                    return ExitCodes.Ok;
                }
            }

            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            LoopController controller = new LoopController(baseFolder, testMode);
            app.DispatcherUnhandledException += controller.OnUnhandledException;
            app.Run();
            GC.KeepAlive(controller);
            ReleaseGate();
            return ExitCodes.Ok;
        }

        public static string Describe(Exception error)
        {
            if (error == null)
            {
                return "unknown failure";
            }
            Exception root = error;
            while (root.InnerException != null)
            {
                root = root.InnerException;
            }
            string message = (root.Message ?? string.Empty).Replace("\r", " ").Replace("\n", " ").Trim();
            return string.Format("{0} (0x{1:X8}): {2}", root.GetType().Name, root.HResult, message);
        }

        public static void ReportTest(string detail)
        {
            if (string.IsNullOrEmpty(TestResultPath))
            {
                return;
            }
            try
            {
                File.WriteAllText(TestResultPath, detail ?? string.Empty);
            }
            catch (Exception)
            {
            }
        }

        public static void Relaunch()
        {
            Process current = Process.GetCurrentProcess();
            bool settled = (DateTime.Now - current.StartTime).TotalSeconds > 30;
            string executable = current.MainModule.FileName;
            ReleaseGate();
            if (settled)
            {
                Process.Start(executable);
            }
            Environment.Exit(settled ? ExitCodes.Ok : ExitCodes.Crashed);
        }

        private static void OnDomainException(object sender, UnhandledExceptionEventArgs e)
        {
            ReportTest(Describe(e.ExceptionObject as Exception));
        }

        private static void ReleaseGate()
        {
            if (gate == null)
            {
                return;
            }
            try
            {
                gate.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
            gate.Dispose();
            gate = null;
        }
    }

    internal sealed class Native
    {
        public const uint EsContinuous = 0x80000000;
        public const uint EsSystemRequired = 0x00000001;
        public const uint EsDisplayRequired = 0x00000002;
        public const uint SpiSetScreenSaveActive = 0x0011;
        public const int WmPowerBroadcast = 0x0218;
        public const int PbtResumeSuspend = 0x0007;
        public const int PbtResumeAutomatic = 0x0012;
        public const int WmSysCommand = 0x0112;
        public const int ScMonitorPower = 0xF170;
        public const int MonitorOff = 2;
        public const int MonitorOn = -1;
        public const int HwndBroadcast = 0xFFFF;

        [StructLayout(LayoutKind.Sequential)]
        public struct LastInput
        {
            public uint Size;
            public uint Time;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MouseInput
        {
            public int Dx;
            public int Dy;
            public uint MouseData;
            public uint Flags;
            public uint Time;
            public IntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct InputRecord
        {
            public uint Type;
            public MouseInput Mouse;
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetLastInputInfo(ref LastInput info);

        [DllImport("kernel32.dll")]
        public static extern uint GetTickCount();

        [DllImport("kernel32.dll")]
        public static extern uint SetThreadExecutionState(uint flags);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr handle);

        [DllImport("user32.dll")]
        public static extern uint SendInput(uint count, InputRecord[] inputs, int size);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SystemParametersInfo(uint action, uint param, IntPtr data, uint flags);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr handle, int message, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int GetSystemMetrics(int index);

        public static uint LastInputTick()
        {
            LastInput info = new LastInput();
            info.Size = (uint)Marshal.SizeOf(typeof(LastInput));
            if (GetLastInputInfo(ref info))
            {
                return info.Time;
            }
            return GetTickCount();
        }

        public static void Nudge()
        {
            InputRecord[] inputs = new InputRecord[1];
            inputs[0].Type = 0;
            inputs[0].Mouse.Flags = 0x0001;
            SendInput(1, inputs, Marshal.SizeOf(typeof(InputRecord)));
        }

        public static void MonitorPower(int state)
        {
            SendMessage(new IntPtr(HwndBroadcast), WmSysCommand, new IntPtr(ScMonitorPower), new IntPtr(state));
        }
    }

    internal static class SpecReader
    {
        public static List<KeyValuePair<string, string>> Pairs()
        {
            List<KeyValuePair<string, string>> list = new List<KeyValuePair<string, string>>();
            AddPair(list, "CPU", Cpu());
            AddPair(list, "RAM", Ram());
            AddPair(list, "Disk", Storage());
            AddPair(list, "Screen", Display());
            AddPair(list, "OS", OperatingSystem());
            return list;
        }

        private static void AddPair(List<KeyValuePair<string, string>> list, string label, string value)
        {
            if (!string.IsNullOrEmpty(value))
            {
                list.Add(new KeyValuePair<string, string>(label, value));
            }
        }

        private static string Cpu()
        {
            try
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey("HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", false))
                {
                    if (key != null)
                    {
                        object value = key.GetValue("ProcessorNameString");
                        if (value != null)
                        {
                            return Collapse(value.ToString());
                        }
                    }
                }
            }
            catch (Exception)
            {
            }
            return string.Empty;
        }

        private static string Ram()
        {
            try
            {
                MemoryStatus status = new MemoryStatus();
                status.Length = (uint)Marshal.SizeOf(typeof(MemoryStatus));
                if (GlobalMemoryStatusEx(ref status))
                {
                    double gigabytes = status.TotalPhysical / 1073741824.0;
                    return Math.Round(gigabytes).ToString(CultureInfo.InvariantCulture) + " GB";
                }
            }
            catch (Exception)
            {
            }
            return string.Empty;
        }

        private static string Storage()
        {
            try
            {
                DriveInfo drive = new DriveInfo(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.System)));
                double gigabytes = drive.TotalSize / 1073741824.0;
                if (gigabytes >= 1000.0)
                {
                    return Math.Round(gigabytes / 1000.0, 1).ToString(CultureInfo.InvariantCulture) + " TB";
                }
                return Math.Round(gigabytes).ToString(CultureInfo.InvariantCulture) + " GB";
            }
            catch (Exception)
            {
            }
            return string.Empty;
        }

        private static string Display()
        {
            try
            {
                int width = Native.GetSystemMetrics(0);
                int height = Native.GetSystemMetrics(1);
                if (width > 0 && height > 0)
                {
                    return width.ToString(CultureInfo.InvariantCulture) + " x " + height.ToString(CultureInfo.InvariantCulture);
                }
            }
            catch (Exception)
            {
            }
            return string.Empty;
        }

        private static string OperatingSystem()
        {
            try
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", false))
                {
                    if (key != null)
                    {
                        string product = AsString(key.GetValue("ProductName"));
                        string display = AsString(key.GetValue("DisplayVersion"));
                        object build = key.GetValue("CurrentBuildNumber");
                        if (build != null)
                        {
                            int buildNumber;
                            if (int.TryParse(build.ToString(), out buildNumber) && buildNumber >= 22000 && product.Contains("Windows 10"))
                            {
                                product = product.Replace("Windows 10", "Windows 11");
                            }
                        }
                        if (display.Length > 0)
                        {
                            return Collapse(product + " " + display);
                        }
                        return Collapse(product);
                    }
                }
            }
            catch (Exception)
            {
            }
            return string.Empty;
        }

        private static string AsString(object value)
        {
            return value == null ? string.Empty : value.ToString();
        }

        private static string Collapse(string value)
        {
            if (value == null)
            {
                return string.Empty;
            }
            string[] parts = value.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            return string.Join(" ", parts);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MemoryStatus
        {
            public uint Length;
            public uint MemoryLoad;
            public ulong TotalPhysical;
            public ulong AvailablePhysical;
            public ulong TotalPageFile;
            public ulong AvailablePageFile;
            public ulong TotalVirtual;
            public ulong AvailableVirtual;
            public ulong AvailableExtendedVirtual;
        }

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    }

    internal sealed class LoopScreen
    {
        private readonly LoopController owner;
        private readonly bool primary;
        private readonly bool testMode;
        private readonly Window window;
        private readonly MediaElement video;
        private readonly string videoPath;
        private readonly List<FrameworkElement> panels = new List<FrameworkElement>();
        private bool ready;
        private bool broken;
        private bool shown;

        private static readonly Color Ink = Color.FromRgb(0xF4, 0xF3, 0xEF);

        public LoopScreen(LoopController controller, string videoPath, Rect bounds, bool primary, bool testMode, string logoPath)
        {
            owner = controller;
            this.primary = primary;
            this.testMode = testMode;
            this.videoPath = videoPath;

            double scale = bounds.Height > 0 ? bounds.Height / 1080.0 : 1.0;
            if (scale < 0.5) { scale = 0.5; }

            video = new MediaElement();
            video.LoadedBehavior = MediaState.Manual;
            video.UnloadedBehavior = MediaState.Manual;
            video.Stretch = Stretch.UniformToFill;
            video.IsMuted = true;
            video.Volume = 0.0;
            video.ScrubbingEnabled = false;
            video.MediaOpened += OnMediaOpened;
            video.MediaEnded += OnMediaEnded;
            video.MediaFailed += OnMediaFailed;

            Grid root = new Grid();
            root.Background = Brushes.Black;
            root.Children.Add(video);

            Border shade = new Border();
            shade.IsHitTestVisible = false;
            LinearGradientBrush vign = new LinearGradientBrush();
            vign.StartPoint = new Point(0.5, 0.0);
            vign.EndPoint = new Point(0.5, 1.0);
            vign.GradientStops.Add(new GradientStop(Color.FromArgb(0x00, 0, 0, 0), 0.0));
            vign.GradientStops.Add(new GradientStop(Color.FromArgb(0x00, 0, 0, 0), 0.55));
            vign.GradientStops.Add(new GradientStop(Color.FromArgb(0x66, 0, 0, 0), 1.0));
            shade.Background = vign;
            root.Children.Add(shade);

            FrameworkElement specs = BuildSpecs(scale);
            if (specs != null)
            {
                root.Children.Add(specs);
                panels.Add(specs);
            }

            FrameworkElement notice = BuildNotice(scale);
            root.Children.Add(notice);
            panels.Add(notice);

            FrameworkElement logo = BuildLogo(scale, logoPath);
            if (logo != null)
            {
                root.Children.Add(logo);
                panels.Add(logo);
            }

            window = new Window();
            window.Title = "DORMANT";
            window.WindowStyle = WindowStyle.None;
            window.ResizeMode = ResizeMode.NoResize;
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.WindowState = WindowState.Normal;
            window.Left = bounds.Left;
            window.Top = bounds.Top;
            window.Width = bounds.Width;
            window.Height = bounds.Height;
            window.ShowInTaskbar = false;
            window.ShowActivated = primary;
            window.Topmost = true;
            window.Background = Brushes.Black;
            window.Cursor = Cursors.None;
            window.Content = root;
            window.Closing += OnClosing;

            foreach (FrameworkElement panel in panels)
            {
                panel.Opacity = 0.0;
            }
        }

        public bool Ready { get { return ready; } }

        private SolidColorBrush Faint() { return new SolidColorBrush(Color.FromArgb(0x6B, Ink.R, Ink.G, Ink.B)); }
        private SolidColorBrush Muted() { return new SolidColorBrush(Color.FromArgb(0xAD, Ink.R, Ink.G, Ink.B)); }
        private SolidColorBrush Line() { return new SolidColorBrush(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF)); }

        private Border Card(double scale)
        {
            Border card = new Border();
            card.Background = new SolidColorBrush(Color.FromArgb(0xB8, 0x09, 0x09, 0x0B));
            card.BorderBrush = Line();
            card.BorderThickness = new Thickness(1);
            card.Effect = new DropShadowEffect { BlurRadius = 34 * scale, ShadowDepth = 12 * scale, Direction = 270, Opacity = 0.45, Color = Colors.Black };
            return card;
        }

        private TextBlock Mono(string text, double size, Brush brush)
        {
            TextBlock block = new TextBlock();
            block.Text = text;
            block.FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New");
            block.FontSize = size;
            block.Foreground = brush;
            block.TextWrapping = TextWrapping.NoWrap;
            return block;
        }

        private TextBlock Sans(string text, double size, Brush brush, FontWeight weight)
        {
            TextBlock block = new TextBlock();
            block.Text = text;
            block.FontFamily = new FontFamily("Segoe UI, Arial");
            block.FontSize = size;
            block.FontWeight = weight;
            block.Foreground = brush;
            block.TextWrapping = TextWrapping.Wrap;
            return block;
        }

        private FrameworkElement BuildSpecs(double scale)
        {
            List<KeyValuePair<string, string>> pairs = SpecReader.Pairs();
            if (pairs.Count == 0)
            {
                return null;
            }
            StackPanel stack = new StackPanel();

            TextBlock head = Mono("THIS MACHINE", 11 * scale, Faint());
            head.Margin = new Thickness(0, 0, 0, 9 * scale);
            stack.Children.Add(head);

            Border rule = new Border();
            rule.Height = 1;
            rule.Background = Line();
            rule.Margin = new Thickness(0, 0, 0, 9 * scale);
            stack.Children.Add(rule);

            Grid grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int i = 0; i < pairs.Count; i++)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

                TextBlock label = Mono(pairs[i].Key.ToUpperInvariant(), 10.5 * scale, Faint());
                label.Margin = new Thickness(0, i == 0 ? 0 : 5 * scale, 14 * scale, 0);
                Grid.SetRow(label, i);
                Grid.SetColumn(label, 0);
                grid.Children.Add(label);

                TextBlock value = Sans(pairs[i].Value, 14 * scale, new SolidColorBrush(Ink), FontWeights.Normal);
                value.Margin = new Thickness(0, i == 0 ? 0 : 5 * scale, 0, 0);
                Grid.SetRow(value, i);
                Grid.SetColumn(value, 1);
                grid.Children.Add(value);
            }
            stack.Children.Add(grid);

            Border card = Card(scale);
            card.Padding = new Thickness(18 * scale, 15 * scale, 20 * scale, 16 * scale);
            card.MinWidth = 210 * scale;
            card.MaxWidth = 340 * scale;
            card.HorizontalAlignment = HorizontalAlignment.Left;
            card.VerticalAlignment = VerticalAlignment.Top;
            card.Margin = new Thickness(40 * scale, 40 * scale, 0, 0);
            card.Child = stack;
            return card;
        }

        private FrameworkElement BuildNotice(double scale)
        {
            StackPanel stack = new StackPanel();

            DockPanel meta = new DockPanel();
            meta.Margin = new Thickness(0, 0, 0, 11 * scale);
            TextBlock brand = Mono("AG LIQUIDATION", 11 * scale, Muted());
            DockPanel.SetDock(brand, Dock.Left);
            meta.Children.Add(brand);

            StackPanel state = new StackPanel();
            state.Orientation = Orientation.Horizontal;
            state.HorizontalAlignment = HorizontalAlignment.Right;
            Rectangle dot = new Rectangle();
            dot.Width = 7 * scale;
            dot.Height = 7 * scale;
            dot.Fill = new SolidColorBrush(Ink);
            dot.Margin = new Thickness(0, 0, 8 * scale, 0);
            dot.VerticalAlignment = VerticalAlignment.Center;
            DoubleAnimation pulse = new DoubleAnimation(1.0, 0.25, new Duration(TimeSpan.FromMilliseconds(1200)));
            pulse.AutoReverse = true;
            pulse.RepeatBehavior = RepeatBehavior.Forever;
            dot.BeginAnimation(UIElement.OpacityProperty, pulse);
            state.Children.Add(dot);
            state.Children.Add(Mono("READY TO USE", 11 * scale, Faint()));
            meta.Children.Add(state);
            stack.Children.Add(meta);

            Border rule = new Border();
            rule.Height = 1;
            rule.Background = Line();
            rule.Margin = new Thickness(0, 0, 0, 13 * scale);
            stack.Children.Add(rule);

            TextBlock title = Sans("Ready when you are.", 29 * scale, new SolidColorBrush(Ink), FontWeights.SemiBold);
            title.Margin = new Thickness(0, 0, 0, 11 * scale);
            stack.Children.Add(title);

            TextBlock line1 = Sans("Every computer here comes with its programs fully installed and permanently activated.", 16 * scale, Muted(), FontWeights.Normal);
            line1.Margin = new Thickness(0, 0, 0, 7 * scale);
            line1.LineHeight = 23 * scale;
            stack.Children.Add(line1);

            TextBlock line2 = Sans("Need a program that isn't included? Please ask any AG Liquidation team member. We'll be glad to help.", 16 * scale, Muted(), FontWeights.Normal);
            line2.LineHeight = 23 * scale;
            stack.Children.Add(line2);

            Border rule2 = new Border();
            rule2.Height = 1;
            rule2.Background = Line();
            rule2.Margin = new Thickness(0, 15 * scale, 0, 12 * scale);
            stack.Children.Add(rule2);

            stack.Children.Add(Sans("Thank you for shopping with us.", 13 * scale, Faint(), FontWeights.Normal));

            Border card = Card(scale);
            card.Padding = new Thickness(22 * scale, 20 * scale, 24 * scale, 20 * scale);
            card.Width = 470 * scale;
            card.HorizontalAlignment = HorizontalAlignment.Left;
            card.VerticalAlignment = VerticalAlignment.Bottom;
            card.Margin = new Thickness(40 * scale, 0, 0, 40 * scale);
            card.Child = stack;
            return card;
        }

        private FrameworkElement BuildLogo(double scale, string logoPath)
        {
            if (string.IsNullOrEmpty(logoPath) || !File.Exists(logoPath))
            {
                return null;
            }
            try
            {
                BitmapImage source = new BitmapImage();
                source.BeginInit();
                source.CacheOption = BitmapCacheOption.OnLoad;
                source.UriSource = new Uri(logoPath, UriKind.Absolute);
                source.EndInit();
                source.Freeze();

                Image image = new Image();
                image.Source = source;
                image.Stretch = Stretch.Uniform;
                image.Width = 300 * scale;
                image.HorizontalAlignment = HorizontalAlignment.Right;
                image.VerticalAlignment = VerticalAlignment.Bottom;
                image.Margin = new Thickness(0, 0, 44 * scale, 44 * scale);
                image.Effect = new DropShadowEffect { BlurRadius = 24 * scale, ShadowDepth = 6 * scale, Direction = 270, Opacity = 0.75, Color = Colors.Black };
                return image;
            }
            catch (Exception)
            {
                return null;
            }
        }

        public void ShowWindow()
        {
            window.Show();
            window.Topmost = true;
            if (primary)
            {
                window.Activate();
                IntPtr handle = new WindowInteropHelper(window).Handle;
                if (handle != IntPtr.Zero)
                {
                    Native.SetForegroundWindow(handle);
                }
            }
        }

        public void HideWindow()
        {
            window.Hide();
        }

        public void Start()
        {
            if (video.Source == null)
            {
                try
                {
                    video.Source = new Uri(videoPath, UriKind.Absolute);
                }
                catch (Exception error)
                {
                    owner.OnScreenFailed(ExitCodes.VideoFailed, Program.Describe(error));
                    return;
                }
            }
        }

        public void Play()
        {
            if (broken)
            {
                return;
            }
            try
            {
                video.Position = TimeSpan.Zero;
                video.Play();
            }
            catch (Exception)
            {
            }
            Reveal();
        }

        public void Pause()
        {
            try
            {
                video.Pause();
            }
            catch (Exception)
            {
            }
            Conceal();
        }

        public void Ensure()
        {
            Raise();
            if (broken)
            {
                return;
            }
            if (!shown)
            {
                Play();
                return;
            }
            try
            {
                video.Play();
            }
            catch (Exception)
            {
            }
        }

        public void Raise()
        {
            if (window.IsVisible)
            {
                window.Topmost = false;
                window.Topmost = true;
            }
        }

        private void Reveal()
        {
            shown = true;
            foreach (FrameworkElement panel in panels)
            {
                Fade(panel, 1.0, 900);
            }
        }

        private void Conceal()
        {
            shown = false;
            foreach (FrameworkElement panel in panels)
            {
                panel.BeginAnimation(UIElement.OpacityProperty, null);
                panel.Opacity = 0.0;
            }
        }

        private void Fade(FrameworkElement target, double to, int ms)
        {
            DoubleAnimation animation = new DoubleAnimation(to, new Duration(TimeSpan.FromMilliseconds(ms)));
            animation.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut };
            target.BeginAnimation(UIElement.OpacityProperty, animation);
        }

        private void OnMediaOpened(object sender, RoutedEventArgs e)
        {
            ready = true;
            owner.OnScreenReady(this);
        }

        private void OnMediaEnded(object sender, RoutedEventArgs e)
        {
            if (broken)
            {
                return;
            }
            try
            {
                video.Position = TimeSpan.Zero;
                video.Play();
            }
            catch (Exception)
            {
            }
        }

        private void OnMediaFailed(object sender, ExceptionRoutedEventArgs e)
        {
            broken = true;
            try
            {
                video.Visibility = Visibility.Hidden;
            }
            catch (Exception)
            {
            }
            string detail = e != null && e.ErrorException != null ? Program.Describe(e.ErrorException) : "the video could not be decoded";
            owner.OnScreenFailed(ExitCodes.VideoFailed, detail);
        }

        private void OnClosing(object sender, CancelEventArgs e)
        {
            e.Cancel = true;
            owner.RequestHide();
        }
    }

    internal sealed class LoopController
    {
        private const uint IdleThresholdMs = 30000;
        private const int EnsureEveryTicks = 4;
        private const uint ResumeDebounceMs = 10000;
        private static readonly string[] Formats = new string[] { ".mp4", ".m4v", ".mov", ".webm" };

        private readonly bool testMode;
        private readonly string baseFolder;
        private readonly string nightFlag;
        private readonly string indexPath;
        private readonly Dispatcher dispatcher;
        private readonly List<LoopScreen> screens = new List<LoopScreen>();
        private readonly DispatcherTimer poll;
        private readonly DispatcherTimer relaunch;
        private readonly DispatcherTimer testDeadline;
        private readonly DispatcherTimer testFinish;
        private HwndSource powerSource;
        private bool showing;
        private bool broken;
        private bool resumeSeen;
        private bool nightMode;
        private bool pageOpenedThisCycle;
        private uint lastResumeTick;
        private uint inputAtShow;
        private int showTicks;
        private int readyCount;
        private IntPtr previousForeground;

        public LoopController(string baseFolder, bool testMode)
        {
            this.baseFolder = baseFolder;
            this.testMode = testMode;
            nightFlag = Path.Combine(baseFolder, "night.flag");
            indexPath = Path.Combine(baseFolder, "web", "index.html");
            dispatcher = Dispatcher.CurrentDispatcher;

            string[] videoList = VideoList(baseFolder);
            string logoPath = Path.Combine(baseFolder, "logo.png");
            Rect[] areas = ScreenAreas();
            for (int index = 0; index < areas.Length; index++)
            {
                string name = index < videoList.Length ? videoList[index] : videoList[videoList.Length - 1];
                string videoPath = Path.Combine(baseFolder, name);
                LoopScreen screen = new LoopScreen(this, videoPath, areas[index], index == 0, testMode, logoPath);
                screens.Add(screen);
            }

            HwndSourceParameters parameters = new HwndSourceParameters("DORMANT.Power");
            parameters.Width = 0;
            parameters.Height = 0;
            parameters.WindowStyle = 0;
            powerSource = new HwndSource(parameters);
            powerSource.AddHook(OnPowerMessage);

            poll = CreateTimer(TimeSpan.FromMilliseconds(250), OnPoll);
            relaunch = CreateTimer(TimeSpan.FromSeconds(60), OnRelaunchDue);
            testDeadline = CreateTimer(TimeSpan.FromSeconds(30), OnTestDeadline);
            testFinish = CreateTimer(TimeSpan.FromSeconds(3), OnTestFinished);

            KeepAwake(false);
            Native.SystemParametersInfo(Native.SpiSetScreenSaveActive, 0, IntPtr.Zero, 0);

            foreach (LoopScreen screen in screens)
            {
                screen.Start();
            }

            if (testMode)
            {
                testDeadline.Start();
                dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(ShowLoopForTest));
            }
            else
            {
                poll.Start();
            }
        }

        public static string FirstVideo(string baseFolder)
        {
            string[] list = VideoList(baseFolder);
            if (list.Length > 0)
            {
                string candidate = Path.Combine(baseFolder, list[0]);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            return null;
        }

        private static string[] VideoList(string baseFolder)
        {
            try
            {
                string config = Path.Combine(baseFolder, "videos.txt");
                if (File.Exists(config))
                {
                    string raw = File.ReadAllText(config);
                    string[] parsed = raw.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    List<string> names = new List<string>();
                    foreach (string entry in parsed)
                    {
                        string trimmed = entry.Trim();
                        if (trimmed.Length > 0)
                        {
                            names.Add(trimmed);
                        }
                    }
                    if (names.Count > 0)
                    {
                        return names.ToArray();
                    }
                }
            }
            catch (Exception)
            {
            }
            try
            {
                foreach (string format in Formats)
                {
                    foreach (string file in Directory.GetFiles(baseFolder, "loop" + format))
                    {
                        return new string[] { Path.GetFileName(file) };
                    }
                }
            }
            catch (Exception)
            {
            }
            return new string[] { "loop.mp4" };
        }

        private void ShowLoopForTest()
        {
            ShowLoop(Native.LastInputTick());
        }

        private DispatcherTimer CreateTimer(TimeSpan interval, EventHandler handler)
        {
            DispatcherTimer timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            timer.Interval = interval;
            timer.Tick += handler;
            return timer;
        }

        private Rect[] ScreenAreas()
        {
            List<Rect> list = new List<Rect>();
            try
            {
                foreach (System.Windows.Forms.Screen screen in System.Windows.Forms.Screen.AllScreens)
                {
                    System.Drawing.Rectangle b = screen.Bounds;
                    Rect area = new Rect(b.X, b.Y, b.Width, b.Height);
                    if (screen.Primary)
                    {
                        list.Insert(0, area);
                    }
                    else
                    {
                        list.Add(area);
                    }
                }
            }
            catch (Exception)
            {
            }
            if (list.Count == 0)
            {
                list.Add(new Rect(0, 0, SystemParameters.PrimaryScreenWidth, SystemParameters.PrimaryScreenHeight));
            }
            return list.ToArray();
        }

        public void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
        {
            e.Handled = true;
            if (testMode)
            {
                Program.ReportTest(Program.Describe(e.Exception));
                Environment.Exit(ExitCodes.Crashed);
                return;
            }
            if (showing)
            {
                try
                {
                    HideLoop(false);
                }
                catch (Exception)
                {
                    showing = false;
                }
            }
        }

        public void OnScreenReady(LoopScreen screen)
        {
            readyCount++;
            if (showing)
            {
                screen.Play();
            }
            if (testMode && !testFinish.IsEnabled)
            {
                testDeadline.Stop();
                testFinish.Start();
            }
        }

        public void OnScreenFailed(int code, string detail)
        {
            if (testMode)
            {
                Program.ReportTest(detail);
                Environment.Exit(code);
                return;
            }
            broken = true;
            if (showing)
            {
                HideLoop(false);
            }
            if (!relaunch.IsEnabled)
            {
                relaunch.Start();
            }
        }

        public void RequestHide()
        {
            if (showing)
            {
                HideLoop(true);
            }
        }

        private void OnRelaunchDue(object sender, EventArgs e)
        {
            relaunch.Stop();
            Program.Relaunch();
        }

        private void OnTestDeadline(object sender, EventArgs e)
        {
            testDeadline.Stop();
            Program.ReportTest(readyCount > 0 ? "the page loaded but the video never started" : "the video engine did not start");
            Environment.Exit(ExitCodes.TimedOut);
        }

        private void OnTestFinished(object sender, EventArgs e)
        {
            testFinish.Stop();
            Environment.Exit(ExitCodes.Ok);
        }

        private void KeepAwake(bool allowDisplayOff)
        {
            uint flags = Native.EsContinuous | Native.EsSystemRequired;
            if (!allowDisplayOff)
            {
                flags |= Native.EsDisplayRequired;
            }
            Native.SetThreadExecutionState(flags);
        }

        private void OnPoll(object sender, EventArgs e)
        {
            bool night = File.Exists(nightFlag);
            if (night != nightMode)
            {
                nightMode = night;
                if (nightMode)
                {
                    if (showing)
                    {
                        HideLoop(false);
                    }
                    KeepAwake(true);
                    Native.MonitorPower(Native.MonitorOff);
                }
                else
                {
                    KeepAwake(false);
                    Native.Nudge();
                }
            }

            if (nightMode)
            {
                return;
            }

            uint lastInput = Native.LastInputTick();
            if (showing)
            {
                if (lastInput != inputAtShow)
                {
                    HideLoop(true);
                    return;
                }
                showTicks++;
                if (showTicks % EnsureEveryTicks == 0)
                {
                    foreach (LoopScreen screen in screens)
                    {
                        screen.Ensure();
                    }
                }
                return;
            }

            if (broken)
            {
                return;
            }

            uint idle = unchecked(Native.GetTickCount() - lastInput);
            if (idle >= IdleThresholdMs)
            {
                ShowLoop(lastInput);
            }
        }

        private void ShowLoop(uint lastInput)
        {
            showing = true;
            showTicks = 0;
            pageOpenedThisCycle = false;
            inputAtShow = lastInput;
            previousForeground = Native.GetForegroundWindow();
            if (!testMode)
            {
                CloseOpenApps();
            }
            foreach (LoopScreen screen in screens)
            {
                screen.ShowWindow();
                screen.Play();
            }
        }

        private void HideLoop(bool openPage)
        {
            showing = false;
            foreach (LoopScreen screen in screens)
            {
                screen.Pause();
                screen.HideWindow();
            }
            IntPtr target = previousForeground;
            previousForeground = IntPtr.Zero;
            if (target != IntPtr.Zero)
            {
                Native.SetForegroundWindow(target);
            }
            if (openPage && !testMode && !pageOpenedThisCycle)
            {
                pageOpenedThisCycle = true;
                OpenIndexPage();
            }
        }

        private void OpenIndexPage()
        {
            if (!File.Exists(indexPath))
            {
                return;
            }
            try
            {
                ProcessStartInfo info = new ProcessStartInfo(indexPath);
                info.UseShellExecute = true;
                Process.Start(info);
            }
            catch (Exception)
            {
            }
        }

        private void CloseOpenApps()
        {
            string ownName = string.Empty;
            try
            {
                ownName = Process.GetCurrentProcess().ProcessName;
            }
            catch (Exception)
            {
            }
            string[] keep = new string[] { ownName, "explorer", "dwm", "textinputhost", "searchhost", "shellexperiencehost", "startmenuexperiencehost", "applicationframehost", "systemsettings", "lockapp" };
            Process[] all;
            try
            {
                all = Process.GetProcesses();
            }
            catch (Exception)
            {
                return;
            }
            foreach (Process process in all)
            {
                try
                {
                    if (process.MainWindowHandle == IntPtr.Zero)
                    {
                        continue;
                    }
                    string name = process.ProcessName.ToLowerInvariant();
                    bool skip = false;
                    foreach (string allowed in keep)
                    {
                        if (name == allowed)
                        {
                            skip = true;
                            break;
                        }
                    }
                    if (skip)
                    {
                        continue;
                    }
                    process.Kill();
                }
                catch (Exception)
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
        }

        private IntPtr OnPowerMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == Native.WmPowerBroadcast)
            {
                int kind = wParam.ToInt32();
                if (kind == Native.PbtResumeAutomatic || kind == Native.PbtResumeSuspend)
                {
                    dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(OnResume));
                }
            }
            return IntPtr.Zero;
        }

        private void OnResume()
        {
            uint now = Native.GetTickCount();
            if (resumeSeen && unchecked(now - lastResumeTick) < ResumeDebounceMs)
            {
                return;
            }
            resumeSeen = true;
            lastResumeTick = now;
            if (showing)
            {
                HideLoop(false);
            }
            KeepAwake(nightMode);
            Native.Nudge();
        }
    }
}
'@

$script:PageTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DORMANT</title>
<style>
:root {
  --unit: 1.05vw;
  --ink: #f4f3ef;
  --muted: rgba(244, 243, 239, 0.68);
  --faint: rgba(244, 243, 239, 0.42);
  --line: rgba(255, 255, 255, 0.14);
  --panel: rgba(9, 9, 11, 0.70);
  --ease: cubic-bezier(0.16, 0.84, 0.24, 1);
}
@media (max-width: 1238px) { :root { --unit: 13px; } }
@media (min-width: 2477px) { :root { --unit: 26px; } }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 100%; height: 100%; overflow: hidden; background: #000; cursor: none; -webkit-user-select: none; user-select: none; }
#loop { position: fixed; top: 0; right: 0; bottom: 0; left: 0; width: 100%; height: 100%; object-fit: cover; background: #000; }
.shade { position: fixed; top: 0; right: 0; bottom: 0; left: 0; pointer-events: none; background:
  radial-gradient(ellipse 60% 55% at 0% 100%, rgba(0, 0, 0, 0.52) 0%, rgba(0, 0, 0, 0) 68%),
  radial-gradient(ellipse 55% 50% at 100% 100%, rgba(0, 0, 0, 0.48) 0%, rgba(0, 0, 0, 0) 66%),
  radial-gradient(ellipse 45% 45% at 0% 0%, rgba(0, 0, 0, 0.46) 0%, rgba(0, 0, 0, 0) 62%); }

.panel {
  position: fixed;
  color: var(--ink);
  opacity: 0;
  transform: translateY(calc(var(--unit) * 0.9));
  transition: opacity 900ms var(--ease), transform 900ms var(--ease);
  font-family: "Segoe UI Variable Display", "Segoe UI", -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
}
.panel.in { opacity: 1; transform: translateY(0); }

.notice {
  left: calc(var(--unit) * 2.4);
  bottom: calc(var(--unit) * 2.4);
  width: calc(var(--unit) * 23);
  max-width: calc(52vw - var(--unit) * 3);
  padding: calc(var(--unit) * 1.1) calc(var(--unit) * 1.25) calc(var(--unit) * 1);
  background: var(--panel);
  border: 1px solid var(--line);
  -webkit-backdrop-filter: blur(20px) saturate(140%);
  backdrop-filter: blur(20px) saturate(140%);
  box-shadow: 0 calc(var(--unit) * 1.2) calc(var(--unit) * 3) rgba(0, 0, 0, 0.45);
}
.notice.in { transition-delay: 500ms; }
.notice::before { content: ""; position: absolute; top: -1px; bottom: -1px; left: -1px; width: 2px; background: var(--ink); }
.notice::after { content: ""; position: absolute; top: 0; right: 0; bottom: 0; left: 0; pointer-events: none; opacity: 0.06; mix-blend-mode: overlay; background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>"); }
.meta { display: flex; justify-content: space-between; align-items: center; padding-bottom: calc(var(--unit) * 0.7); margin-bottom: calc(var(--unit) * 0.85); border-bottom: 1px solid var(--line); font-family: "Cascadia Mono", "SF Mono", Menlo, Consolas, monospace; font-size: calc(var(--unit) * 0.56); letter-spacing: 0.24em; color: var(--faint); white-space: nowrap; }
.brand { color: var(--muted); margin-right: var(--unit); }
.state { display: inline-flex; align-items: center; }
.state i { display: inline-block; width: 0.55em; height: 0.55em; margin-right: 0.8em; background: var(--ink); animation: pulse 2.4s ease-in-out infinite; }
.notice h1 { font-size: calc(var(--unit) * 1.2); font-weight: 600; line-height: 1.15; letter-spacing: -0.01em; margin-bottom: calc(var(--unit) * 0.55); }
.notice p { font-size: calc(var(--unit) * 0.8); line-height: 1.5; color: var(--muted); }
.notice p + p { margin-top: calc(var(--unit) * 0.4); }
.notice strong { color: var(--ink); font-weight: 600; }
.notice footer { margin-top: calc(var(--unit) * 0.85); padding-top: calc(var(--unit) * 0.7); border-top: 1px solid var(--line); font-size: calc(var(--unit) * 0.66); letter-spacing: 0.02em; color: var(--faint); }

.mark {
  right: calc(var(--unit) * 2.4);
  bottom: calc(var(--unit) * 2.4);
  width: calc(var(--unit) * 13);
  max-width: calc(40vw - var(--unit) * 2.4);
}
.mark.in { transition-delay: 700ms; }
.mark.missing { display: none; }
.mark img { display: block; width: 100%; height: auto; filter: drop-shadow(0 calc(var(--unit) * 0.25) calc(var(--unit) * 0.7) rgba(0, 0, 0, 0.75)) drop-shadow(0 0 calc(var(--unit) * 1.4) rgba(0, 0, 0, 0.55)); }

.specs {
  left: calc(var(--unit) * 2.4);
  top: calc(var(--unit) * 2.4);
  min-width: calc(var(--unit) * 14);
  max-width: calc(var(--unit) * 20);
  padding: calc(var(--unit) * 0.85) calc(var(--unit) * 1.05) calc(var(--unit) * 0.9);
  background: var(--panel);
  border: 1px solid var(--line);
  -webkit-backdrop-filter: blur(20px) saturate(140%);
  backdrop-filter: blur(20px) saturate(140%);
  box-shadow: 0 calc(var(--unit) * 1.2) calc(var(--unit) * 3) rgba(0, 0, 0, 0.45);
}
.specs.in { transition-delay: 600ms; }
.specs.empty { display: none; }
.specs::before { content: ""; position: absolute; top: -1px; bottom: -1px; left: -1px; width: 2px; background: var(--ink); }
.specs .head { font-family: "Cascadia Mono", "SF Mono", Menlo, Consolas, monospace; font-size: calc(var(--unit) * 0.52); letter-spacing: 0.24em; color: var(--faint); padding-bottom: calc(var(--unit) * 0.6); margin-bottom: calc(var(--unit) * 0.6); border-bottom: 1px solid var(--line); }
.specs dl { display: grid; grid-template-columns: auto 1fr; gap: calc(var(--unit) * 0.3) calc(var(--unit) * 0.9); }
.specs dt { font-family: "Cascadia Mono", "SF Mono", Menlo, Consolas, monospace; font-size: calc(var(--unit) * 0.52); letter-spacing: 0.1em; color: var(--faint); text-transform: uppercase; align-self: baseline; }
.specs dd { font-size: calc(var(--unit) * 0.72); line-height: 1.3; color: var(--ink); }

@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.25; } }
</style>
</head>
<body>
<video id="loop" loop muted playsinline preload="auto" disablepictureinpicture disableremoteplayback></video>
<div class="shade"></div>

<aside class="specs empty panel" id="specs">
  <div class="head">THIS MACHINE</div>
  <dl id="specsList"></dl>
</aside>

<aside class="notice panel" id="notice">
  <div class="meta"><span class="brand">AG LIQUIDATION</span><span class="state"><i></i>READY TO USE</span></div>
  <h1>Ready when you are.</h1>
  <p>Every computer here comes with its programs fully installed and permanently activated.</p>
  <p>Need a program that isn't included? Please ask any <strong>AG Liquidation</strong> team member. We'll be glad to help.</p>
  <footer>Thank you for shopping with us.</footer>
</aside>

<div class="mark panel" id="mark"><img id="markImage" src="logo.png" alt="AG Liquidation"></div>

<script>
(function () {
  var SPEC_ORDER = ['cpu', 'ram', 'storage', 'display', 'os'];
  var SPEC_LABEL = { cpu: 'CPU', ram: 'RAM', storage: 'Disk', display: 'Screen', os: 'OS' };
  var video = document.getElementById('loop');
  var notice = document.getElementById('notice');
  var mark = document.getElementById('mark');
  var markImage = document.getElementById('markImage');
  var specs = document.getElementById('specs');
  var specsList = document.getElementById('specsList');
  var panels = [specs, notice, mark];
  var broken = false;

  function videoName() {
    var query = window.location.search || '';
    var match = query.match(/[?&]v=([^&]+)/);
    if (match) {
      try {
        return decodeURIComponent(match[1]);
      } catch (error) {
        return match[1];
      }
    }
    return 'loop.mp4';
  }

  function report(state) {
    try {
      document.title = 'dormant:' + state;
    } catch (error) {
    }
    try {
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(state);
      }
    } catch (error) {
    }
  }

  function play() {
    if (broken) {
      return;
    }
    var attempt = video.play();
    if (attempt && typeof attempt.catch === 'function') {
      attempt.catch(function () {});
    }
  }

  function conceal() {
    for (var index = 0; index < panels.length; index += 1) {
      panels[index].style.transition = 'none';
      panels[index].classList.remove('in');
    }
  }

  function reveal() {
    conceal();
    void notice.offsetWidth;
    for (var index = 0; index < panels.length; index += 1) {
      panels[index].style.transition = '';
      panels[index].classList.add('in');
    }
  }

  function escapeText(value) {
    return String(value).replace(/[&<>]/g, function (character) {
      if (character === '&') { return '&amp;'; }
      if (character === '<') { return '&lt;'; }
      return '&gt;';
    });
  }

  function applySpecs(data) {
    if (!data || typeof data !== 'object') {
      return;
    }
    var rows = '';
    for (var index = 0; index < SPEC_ORDER.length; index += 1) {
      var key = SPEC_ORDER[index];
      var value = data[key];
      if (value === undefined || value === null || String(value).length === 0) {
        continue;
      }
      rows += '<dt>' + SPEC_LABEL[key] + '</dt><dd>' + escapeText(value) + '</dd>';
    }
    if (rows.length === 0) {
      return;
    }
    specsList.innerHTML = rows;
    specs.classList.remove('empty');
    if (notice.classList.contains('in')) {
      specs.classList.add('in');
    }
  }

  markImage.addEventListener('error', function () {
    mark.classList.add('missing');
  });
  video.addEventListener('playing', function () {
    report('playing');
  });
  video.addEventListener('error', function () {
    broken = true;
    video.style.visibility = 'hidden';
    report('error');
  });

  video.src = videoName();

  window.dormant = {
    setSpecs: function (data) {
      try {
        applySpecs(typeof data === 'string' ? JSON.parse(data) : data);
      } catch (error) {
      }
    },
    show: function () {
      if (!broken) {
        try {
          video.currentTime = 0;
        } catch (error) {
        }
      }
      play();
      reveal();
    },
    hide: function () {
      video.pause();
      conceal();
    },
    ensure: function () {
      if (!notice.classList.contains('in')) {
        this.show();
        return;
      }
      if (video.paused && !broken) {
        play();
      }
    }
  };
})();
</script>
</body>
</html>
'@

function Initialize-Console {
    try {
        $raw = $Host.UI.RawUI
        $raw.WindowTitle = 'DORMANT // setup'
        $raw.BackgroundColor = 'Black'
        $raw.ForegroundColor = 'Gray'
    }
    catch {
    }
    Clear-Host
}

function Write-Line {
    param(
        [string]$Text = '',
        [ConsoleColor]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Rule {
    Write-Line '  -----------------------------------------------------' DarkGray
}

function Show-Banner {
    $art = @'

   ____    ___   ____   __  __     _     _   _  _____
  |  _ \  / _ \ |  _ \ |  \/  |   / \   | \ | ||_   _|
  | | | || | | || |_) || |\/| |  / _ \  |  \| |  | |
  | |_| || |_| ||  _ < | |  | | / ___ \ | |\  |  | |
  |____/  \___/ |_| \_\|_|  |_|/_/   \_\|_| \_|  |_|

'@
    Write-Host $art -ForegroundColor White
    Write-Line '  :: power schedule + idle loop system' DarkGray
    Write-Line ('  :: v{0}  //  made by {1}' -f $script:Version, $script:Author) DarkGray
    Write-Line '  :: machines sleep. you clock in.' DarkGray
    Write-Rule
    Write-Line ('  WAKE    mon-sat {0}    sun {1}' -f $script:WakeWeek, $script:WakeSunday)
    Write-Line ('  SLEEP   mon-sat {0}    sun {1}' -f $script:SleepWeek, $script:SleepSunday)
    Write-Line '  LOOP    after 30s of no input'
    Write-Line '  VIDEO   mp4 / mov / m4v / webm'
    Write-Rule
    Write-Line
}

function Read-Choice {
    Write-Line '  [1]  install / update'
    Write-Line '  [2]  uninstall'
    Write-Line '  [3]  exit'
    Write-Line
    Write-Host '  >> ' -ForegroundColor White -NoNewline
    while ($true) {
        $key = [string][Console]::ReadKey($true).KeyChar
        if (@('1', '2', '3') -contains $key) {
            Write-Host $key -ForegroundColor White
            Write-Line
            return $key
        }
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [switch]$Soft
    )
    Write-Host ('  [ .. ] {0}' -f $Label) -ForegroundColor DarkGray -NoNewline
    try {
        & $Action | Out-Null
        Write-Host ("`r  [ OK ] {0}" -f $Label) -ForegroundColor Gray
    }
    catch {
        if ($Soft) {
            Write-Host ("`r  [WARN] {0}" -f $Label) -ForegroundColor DarkYellow
        }
        else {
            Write-Host ("`r  [FAIL] {0}" -f $Label) -ForegroundColor Red
            $script:Failures++
        }
        Write-Host ('         {0}' -f $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Write-Summary {
    param([string]$Success)
    Write-Line
    if ($script:Failures -eq 0) {
        Write-Line ('  >> {0}' -f $Success) White
    }
    else {
        Write-Line ('  >> finished with {0} error(s). check the lines marked FAIL.' -f $script:Failures) Red
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        if (-not $detail) {
            $detail = 'exit code ' + $LASTEXITCODE
        }
        throw ('{0}: {1}' -f [System.IO.Path]::GetFileName($FilePath), $detail)
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    if (-not (Test-Path -LiteralPath $OutFile) -or (Get-Item -LiteralPath $OutFile).Length -le 0) {
        throw ('download failed: {0}' -f $Uri)
    }
}

function Get-MonitorCount {
    Add-Type -AssemblyName System.Windows.Forms
    try {
        return @([System.Windows.Forms.Screen]::AllScreens).Count
    }
    catch {
        return 1
    }
}

function Select-OneVideo {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Prompt
    $dialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $dialog.Filter = 'Video (*.mp4;*.mov;*.m4v;*.webm)|*.mp4;*.mov;*.m4v;*.webm'
    $dialog.Multiselect = $false
    $dialog.CheckFileExists = $true
    $dialog.RestoreDirectory = $true
    try {
        if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    }
    finally {
        $dialog.Dispose()
        $owner.Dispose()
    }
}

function Select-Videos {
    $count = Get-MonitorCount
    $result = @()
    if ($count -le 1) {
        $one = Select-OneVideo -Prompt 'DORMANT // choose the loop video'
        if (-not $one) { return $null }
        return @($one)
    }
    for ($index = 1; $index -le $count; $index++) {
        $one = Select-OneVideo -Prompt ('DORMANT // choose the video for monitor {0} of {1}' -f $index, $count)
        if (-not $one) { return $null }
        $result += $one
    }
    return $result
}

function Stop-Loop {
    $running = @(Get-Process -Name 'DORMANT' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    }
}

function Remove-Tasks {
    $existing = @(Get-ScheduledTask -TaskPath $script:TaskPath -ErrorAction SilentlyContinue)
    foreach ($task in $existing) {
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
    }
}

function Remove-TaskFolder {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $rootFolder = $service.GetFolder('\')
    $names = @($rootFolder.GetFolders(0) | ForEach-Object { $_.Name })
    if ($names -contains 'DORMANT') {
        $rootFolder.DeleteFolder('DORMANT', 0)
    }
}

function Initialize-Root {
    if (-not (Test-Path -LiteralPath $script:Root)) {
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
    }
    foreach ($pattern in @('loop*.mp4', 'loop*.mov', 'loop*.m4v', 'loop*.webm', 'logo.*', 'wallpaper.*', 'wallpaper-ultrawide.*', 'videos.txt', 'night.flag')) {
        Get-ChildItem -LiteralPath $script:Root -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    $webTarget = Join-Path $script:Root 'web'
    if (Test-Path -LiteralPath $webTarget) {
        Remove-Item -LiteralPath $webTarget -Recurse -Force
    }
    foreach ($name in @('DORMANT.exe', 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll', 'WebView2Loader.dll')) {
        $stale = Join-Path $script:Root $name
        if (Test-Path -LiteralPath $stale) {
            Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
        }
    }
    $runtimesTarget = Join-Path $script:Root 'runtimes'
    if (Test-Path -LiteralPath $runtimesTarget) {
        Remove-Item -LiteralPath $runtimesTarget -Recurse -Force
    }
}

function Copy-Videos {
    param([Parameter(Mandatory = $true)][string[]]$Sources)
    $names = @()
    for ($index = 0; $index -lt $Sources.Count; $index++) {
        $source = $Sources[$index]
        $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
        if ($script:Formats -notcontains $extension) {
            throw ('unsupported format {0}' -f $extension)
        }
        if ((Get-Item -LiteralPath $source).Length -le 0) {
            throw 'one of the selected videos is empty'
        }
        $name = if ($index -eq 0) { 'loop' + $extension } else { ('loop{0}{1}' -f ($index + 1), $extension) }
        Copy-Item -LiteralPath $source -Destination (Join-Path $script:Root $name) -Force
        $names += $name
    }
    [System.IO.File]::WriteAllText((Join-Path $script:Root 'videos.txt'), ($names -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $names[0]
}

function Find-UsbAsset {
    param([Parameter(Mandatory = $true)][string[]]$RelativePaths)
    $cursor = Split-Path -Parent $env:DORMANT_SELF
    while ($cursor) {
        foreach ($relative in $RelativePaths) {
            $candidate = Join-Path $cursor $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }
    return $null
}

function Copy-Logo {
    $logo = Find-UsbAsset -RelativePaths $script:LogoPaths
    if (-not $logo) {
        throw 'AgLogo\AgLogo.png was not found on the USB. the loop runs without the logo.'
    }
    Copy-Item -LiteralPath $logo -Destination (Join-Path $script:Root 'logo.png') -Force
}

function Copy-Wallpapers {
    $found = 0
    $standard = Find-UsbAsset -RelativePaths $script:WallPaths
    if ($standard) {
        Copy-Item -LiteralPath $standard -Destination (Join-Path $script:Root ('wallpaper' + [System.IO.Path]::GetExtension($standard).ToLowerInvariant())) -Force
        $found++
    }
    $wide = Find-UsbAsset -RelativePaths $script:WidePaths
    if ($wide) {
        Copy-Item -LiteralPath $wide -Destination (Join-Path $script:Root ('wallpaper-ultrawide' + [System.IO.Path]::GetExtension($wide).ToLowerInvariant())) -Force
        $found++
    }
    if ($found -eq 0) {
        throw 'no wallpaper was found in the Walllpapers folder on the USB'
    }
    if (-not $standard) {
        throw 'AgWallpaper (png or jpg) was not found. only the ultrawide wallpaper was copied'
    }
    if (-not $wide) {
        throw 'AgWallpaperUltraw (png or jpg) was not found. ultrawide screens use the normal wallpaper'
    }
}

function Copy-Web {
    $source = $null
    foreach ($relative in $script:WebDirs) {
        $candidate = Find-UsbAsset -RelativePaths @($relative + '\index.html')
        if ($candidate) {
            $source = Split-Path -Parent $candidate
            break
        }
    }
    if (-not $source) {
        throw 'the Web folder with index.html was not found on the USB. the page will not open after the loop.'
    }
    $target = Join-Path $script:Root 'web'
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $target 'index.html'))) {
        throw 'index.html was not copied'
    }
}

function New-Uninstaller {
    Copy-Item -LiteralPath $env:DORMANT_SELF -Destination $script:Uninstaller -Force
}

function Remove-Uninstaller {
    if ($script:UninstallMode) {
        return
    }
    if (Test-Path -LiteralPath $script:Uninstaller) {
        Remove-Item -LiteralPath $script:Uninstaller -Force
    }
}

function Restore-Wallpaper {
    $marker = Join-Path $env:LOCALAPPDATA 'DORMANT\previous-wallpaper.txt'
    if (-not (Test-Path -LiteralPath $marker)) {
        return
    }
    $lines = @([System.IO.File]::ReadAllLines($marker))
    $image = if ($lines.Count -gt 0) { $lines[0] } else { '' }
    $style = if ($lines.Count -gt 1 -and $lines[1]) { $lines[1] } else { '10' }
    $tile = if ($lines.Count -gt 2 -and $lines[2]) { $lines[2] } else { '0' }
    $target = ''
    if ($image -and (Test-Path -LiteralPath $image)) {
        $themes = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
        New-Item -ItemType Directory -Path $themes -Force | Out-Null
        $target = Join-Path $themes ('DORMANT-restored' + [System.IO.Path]::GetExtension($image))
        Copy-Item -LiteralPath $image -Destination $target -Force
    }
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value $style
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value $tile
    if (-not ('Dormant.Wallpaper' -as [type])) {
        Add-Type -Namespace 'Dormant' -Name 'Wallpaper' -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfoW")] public static extern bool Set(uint action, uint param, string data, uint flags);'
    }
    [void][Dormant.Wallpaper]::Set(0x0014, 0, $target, 3)
}

function Remove-SelfLater {
    $command = '/c ping -n 3 127.0.0.1 >nul & del /f /q "{0}"' -f $env:DORMANT_SELF
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -ArgumentList $command -WindowStyle Hidden
}

function Write-Page {
    [System.IO.File]::WriteAllText($script:PagePath, $script:PageTemplate, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-WebView2RuntimeVersion {
    $paths = @(
        ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{0}' -f $script:WebView2Id),
        ('HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{0}' -f $script:WebView2Id),
        ('HKCU:\Software\Microsoft\EdgeUpdate\Clients\{0}' -f $script:WebView2Id)
    )
    $best = $null
    foreach ($path in $paths) {
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item -and $item.PSObject.Properties['pv']) {
            $raw = [string]$item.pv
            if ($raw -and $raw -ne '0.0.0.0') {
                $parsed = $null
                if ([Version]::TryParse($raw, [ref]$parsed)) {
                    if (-not $best -or $parsed -gt $best) {
                        $best = $parsed
                    }
                }
            }
        }
    }
    return $best
}

function Test-WebView2Runtime {
    return $null -ne (Get-WebView2RuntimeVersion)
}

function Install-WebView2Runtime {
    $setup = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'
    Invoke-Download -Uri $script:WebView2Setup -OutFile $setup
    try {
        Start-Process -FilePath $setup -ArgumentList '/silent', '/install' -Wait | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue
    }
}

function Confirm-WebView2Runtime {
    $required = [Version]$script:WebView2SdkVer
    $installed = Get-WebView2RuntimeVersion
    if ($installed -and $installed -ge $required) {
        return
    }
    Install-WebView2Runtime
    $installed = Get-WebView2RuntimeVersion
    if (-not $installed) {
        throw 'the WebView2 runtime could not be installed'
    }
    if ($installed -lt $required) {
        throw ('the WebView2 runtime on this PC is {0}, older than the {1} this build needs. connect to the internet and run the installer again so Windows can update it.' -f $installed, $required)
    }
}

function Get-LoaderArchitecture {
    $os = $null
    try {
        $os = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    }
    catch {
    }
    if ($os -eq 'Arm64') {
        return 'arm64'
    }
    if ([Environment]::Is64BitOperatingSystem) {
        return 'x64'
    }
    return 'x86'
}

function Test-SdkPackage {
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    }
    catch {
        return $false
    }
    try {
        $core = @($archive.Entries | Where-Object { $_.FullName -match '^lib/net4[0-9]*/Microsoft\.Web\.WebView2\.Core\.dll$' })
        if ($core.Count -le 0) {
            return $false
        }
        $spec = $archive.Entries | Where-Object { $_.FullName -match '(?i)\.nuspec$' } | Select-Object -First 1
        if (-not $spec) {
            return $false
        }
        $reader = New-Object System.IO.StreamReader($spec.Open())
        try {
            $text = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        $match = [regex]::Match($text, '<version>\s*([^<\s]+)\s*</version>')
        if (-not $match.Success) {
            return $false
        }
        return $match.Groups[1].Value -eq $script:WebView2SdkVer
    }
    finally {
        $archive.Dispose()
    }
}

function Get-DownloadProblem {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] 64
            $count = $stream.Read($buffer, 0, $buffer.Length)
        }
        finally {
            $stream.Dispose()
        }
        $head = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count).TrimStart()
        if ($head.StartsWith('<')) {
            return 'the network sent a web page instead of the file (public WiFi login page?). finish the WiFi login or use another network, then run the installer again.'
        }
    }
    catch {
    }
    return 'the download came back incomplete. check the internet connection and run the installer again.'
}

function Test-SdkInstalled {
    $architecture = Get-LoaderArchitecture
    $required = @()
    foreach ($name in $script:SdkFiles) {
        $required += (Join-Path $script:Root $name)
    }
    $required += (Join-Path $script:Root 'WebView2Loader.dll')
    $required += (Join-Path $script:Root ('runtimes\win-{0}\native\WebView2Loader.dll' -f $architecture))
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -le 0) {
            return $false
        }
    }
    foreach ($name in $script:SdkFiles) {
        try {
            [void][System.Reflection.AssemblyName]::GetAssemblyName((Join-Path $script:Root $name))
        }
        catch {
            return $false
        }
    }
    return $true
}

function Get-WebView2Package {
    $cached = Find-UsbAsset -RelativePaths $script:CachePaths
    if ($cached) {
        if (Test-SdkPackage -Path $cached) {
            return $cached
        }
        Remove-Item -LiteralPath $cached -Force -ErrorAction SilentlyContinue
    }

    $temp = Join-Path $env:TEMP ('dormant-webview2-{0}.nupkg' -f [guid]::NewGuid().ToString('N'))
    $problem = 'the WebView2 components could not be downloaded'
    $valid = $false
    for ($attempt = 1; $attempt -le 3 -and -not $valid; $attempt++) {
        try {
            Invoke-Download -Uri $script:WebView2Sdk -OutFile $temp
            if (Test-SdkPackage -Path $temp) {
                $valid = $true
            }
            else {
                $problem = Get-DownloadProblem -Path $temp
            }
        }
        catch {
            $problem = $_.Exception.Message
        }
        if (-not $valid) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
    if (-not $valid) {
        throw $problem
    }

    try {
        if (-not (Test-Path -LiteralPath $script:CacheDir)) {
            New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
        }
        $cached = Join-Path $script:CacheDir 'webview2-sdk.nupkg'
        Copy-Item -LiteralPath $temp -Destination $cached -Force
        if (Test-SdkPackage -Path $cached) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            return $cached
        }
        Remove-Item -LiteralPath $cached -Force -ErrorAction SilentlyContinue
    }
    catch {
    }
    return $temp
}

function Install-WebView2Sdk {
    if (Test-SdkInstalled) {
        return
    }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $package = Get-WebView2Package
    $architecture = Get-LoaderArchitecture
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package)
    try {
        $entries = @($archive.Entries)
        foreach ($name in $script:SdkFiles) {
            $pattern = '^lib/net4[0-9]*/' + [regex]::Escape($name) + '$'
            $entry = $entries | Where-Object { $_.FullName -match $pattern } | Sort-Object FullName -Descending | Select-Object -First 1
            if (-not $entry) {
                throw ('{0} was not found in the WebView2 package' -f $name)
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $script:Root $name), $true)
        }
        foreach ($flavor in $script:LoaderFlavors) {
            $candidates = @(
                ('runtimes/win-{0}/native/WebView2Loader.dll' -f $flavor),
                ('build/native/{0}/WebView2Loader.dll' -f $flavor)
            )
            $loader = $entries | Where-Object { $candidates -contains $_.FullName } | Select-Object -First 1
            if (-not $loader) {
                if ($flavor -eq $architecture) {
                    throw ('WebView2Loader.dll ({0}) was not found in the WebView2 package' -f $flavor)
                }
                continue
            }
            $folder = Join-Path $script:Root ('runtimes\win-{0}\native' -f $flavor)
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($loader, (Join-Path $folder 'WebView2Loader.dll'), $true)
            if ($flavor -eq $architecture) {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($loader, (Join-Path $script:Root 'WebView2Loader.dll'), $true)
            }
        }
    }
    finally {
        $archive.Dispose()
    }
    if (-not (Test-SdkInstalled)) {
        throw 'the WebView2 components could not be installed'
    }
}

function Build-Player {
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms, PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    $references = @(
        [System.Uri].Assembly.Location
        [System.Linq.Enumerable].Assembly.Location
        [System.Drawing.Color].Assembly.Location
        [System.Windows.Forms.Form].Assembly.Location
        [System.Windows.Threading.Dispatcher].Assembly.Location
        [System.Windows.UIElement].Assembly.Location
        [System.Windows.Window].Assembly.Location
        [System.Xaml.XamlSchemaContext].Assembly.Location
    ) | Select-Object -Unique
    if (Test-Path -LiteralPath $script:ExePath) {
        Remove-Item -LiteralPath $script:ExePath -Force
    }
    Add-Type -TypeDefinition $script:PlayerSource -Language CSharp -ReferencedAssemblies $references -OutputAssembly $script:ExePath -OutputType WindowsApplication -IgnoreWarnings
    if (-not (Test-Path -LiteralPath $script:ExePath)) {
        throw 'the compiler produced no output'
    }
}

function Set-Hibernation {
    Invoke-Native -FilePath $script:PowerCfg -Arguments @('/hibernate', 'on')
    Invoke-Native -FilePath $script:PowerCfg -Arguments @('/h', '/type', 'full')
}

function Set-PowerValue {
    param(
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $true)][string]$Value
    )
    foreach ($mode in @('/setacvalueindex', '/setdcvalueindex')) {
        Invoke-Native -FilePath $script:PowerCfg -Arguments @($mode, 'SCHEME_CURRENT', $Group, $Setting, $Value)
    }
    Invoke-Native -FilePath $script:PowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT')
}

function New-WeekTriggers {
    param(
        [Parameter(Mandatory = $true)][string]$WeekTime,
        [Parameter(Mandatory = $true)][string]$SundayTime
    )
    @(
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek $script:Weekdays -At $WeekTime
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $SundayTime
    )
}

function Test-WakeSupported {
    $report = (& $script:PowerCfg '/a') 2>&1 | Out-String
    $hasHibernate = $report -match 'Hibernate'
    $modernStandby = $report -match 'Standby \(S0 Low Power Idle\)'
    $classicStandby = $report -match 'Standby \(S[123]\)'
    if ($hasHibernate -and -not $modernStandby -and $classicStandby) {
        return $true
    }
    if ($hasHibernate -and -not $modernStandby) {
        $devices = (& $script:PowerCfg '-devicequery' 'wake_programmable') 2>&1 | Out-String
        if ($devices.Trim().Length -gt 0) {
            return $true
        }
    }
    return $false
}

function Set-PowerMode {
    param([Parameter(Mandatory = $true)][string]$Mode)
    [System.IO.File]::WriteAllText($script:ModeFile, $Mode, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-NightHelper {
    $flag = $script:NightFlag
    $lines = @(
        '@echo off',
        'if /I "%~1"=="off" ('
        ('    echo locked ^> "{0}"' -f $flag),
        '    exit /b 0',
        ')',
        ('    del /f /q "{0}" >nul 2>&1' -f $flag),
        'exit /b 0'
    )
    [System.IO.File]::WriteAllLines($script:HelperPath, $lines)
}

function Register-NightTask {
    param([Parameter(Mandatory = $true)][bool]$Hibernate)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $triggers = New-WeekTriggers -WeekTime $script:SleepWeek -SundayTime $script:SleepSunday
    if ($Hibernate) {
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\shutdown.exe') -Argument '/h'
        $description = 'DORMANT // hibernate at closing time'
    }
    else {
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\cmd.exe') -Argument ('/c "{0}" off' -f $script:HelperPath)
        $description = 'DORMANT // screen off at closing time'
    }
    Register-ScheduledTask -TaskPath $script:TaskPath -TaskName 'Night' -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description $description -Force | Out-Null
}

function Register-WakeTask {
    param([Parameter(Mandatory = $true)][bool]$Hibernate)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $triggers = New-WeekTriggers -WeekTime $script:WakeWeek -SundayTime $script:WakeSunday
    if ($Hibernate) {
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\cmd.exe') -Argument '/c exit 0'
        $settings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    }
    else {
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\cmd.exe') -Argument ('/c "{0}" on' -f $script:HelperPath)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    }
    Register-ScheduledTask -TaskPath $script:TaskPath -TaskName 'Wake' -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'DORMANT // wake at opening time' -Force | Out-Null
}

function Register-LoopTask {
    $action = New-ScheduledTaskAction -Execute $script:ExePath -WorkingDirectory $script:Root
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 4 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $trigger.Repetition = $watchdog.Repetition
    Register-ScheduledTask -TaskPath $script:TaskPath -TaskName 'Loop' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'DORMANT // idle video loop' -Force | Out-Null
}

function Start-Loop {
    $shell = Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $shell) {
        throw 'no desktop session found. the loop starts at the next sign-in.'
    }
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"{0}"' -f $script:ExePath)
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (Get-Process -Name 'DORMANT' -ErrorAction SilentlyContinue) {
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'the loop did not start now. it will start at the next sign-in.'
}

function Test-Playback {
    $resultFile = Join-Path $env:TEMP ('dormant-test-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $process = Start-Process -FilePath $script:ExePath -ArgumentList @('--test', ('"{0}"' -f $resultFile)) -WorkingDirectory $script:Root -PassThru
    $null = $process.Handle
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'the playback test did not finish in time'
    }
    $detail = ''
    if (Test-Path -LiteralPath $resultFile) {
        $detail = ([System.IO.File]::ReadAllText($resultFile)).Trim()
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
    $reason = switch ($process.ExitCode) {
        0 { $null }
        10 { 'WebView2 could not start on this PC' }
        11 { 'the loop page could not be loaded' }
        12 { 'this PC cannot play this video file. an H.264 .mp4 is the safest choice' }
        13 { 'the video did not start within 30 seconds' }
        14 { 'the loop page is missing' }
        15 { 'the player crashed' }
        default { 'the player stopped unexpectedly (code 0x{0:X8})' -f $process.ExitCode }
    }
    if (-not $reason) {
        return
    }
    if ($detail) {
        throw ('{0}{1}         {2}' -f $reason, [Environment]::NewLine, $detail)
    }
    throw $reason
}

function Remove-Root {
    if (Test-Path -LiteralPath $script:Root) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force
    }
}

function Remove-UserData {
    $folder = Join-Path $env:LOCALAPPDATA 'DORMANT'
    if (Test-Path -LiteralPath $folder) {
        Start-Sleep -Seconds 2
        Remove-Item -LiteralPath $folder -Recurse -Force
    }
}

function Install-Dormant {
    Write-Line '  >> choose the video that will loop on this machine' White
    $videos = Select-Videos
    if (-not $videos) {
        Write-Line '  :: no video selected. nothing was changed.' DarkGray
        return
    }
    foreach ($entry in $videos) {
        Write-Line ('  :: {0}' -f [System.IO.Path]::GetFileName($entry)) DarkGray
    }
    Write-Line

    $script:VideoName = $null
    $script:Hibernate = $false
    Invoke-Step 'stopping previous instance' { Stop-Loop; Remove-Tasks }
    Invoke-Step 'preparing install folder' { Initialize-Root; Remove-Item -LiteralPath $script:NightFlag -Force -ErrorAction SilentlyContinue }
    Invoke-Step 'copying video' { $script:VideoName = Copy-Videos -Sources $videos }
    Invoke-Step 'copying logo' { Copy-Logo } -Soft
    Invoke-Step 'copying wallpapers' { Copy-Wallpapers } -Soft
    Invoke-Step 'copying web page' { Copy-Web } -Soft
    Invoke-Step 'building player' { Build-Player }
    Invoke-Step 'testing playback (the video shows for a moment)' { Test-Playback }
    Invoke-Step 'enabling full hibernation' { Set-Hibernation }
    Invoke-Step 'allowing wake timers' { Set-PowerValue -Group 'SUB_SLEEP' -Setting 'RTCWAKE' -Value '1' }
    Invoke-Step 'skipping sign-in on wake' { Set-PowerValue -Group 'SUB_NONE' -Setting 'CONSOLELOCK' -Value '0' } -Soft
    Invoke-Step 'checking wake support' { $script:Hibernate = Test-WakeSupported; Set-PowerMode ([string]$script:Hibernate); Write-NightHelper }
    Invoke-Step 'scheduling sleep' { Register-NightTask -Hibernate $script:Hibernate }
    Invoke-Step 'scheduling wake' { Register-WakeTask -Hibernate $script:Hibernate }
    Invoke-Step 'registering idle loop' { Register-LoopTask }
    Invoke-Step 'starting idle loop' { Start-Loop } -Soft
    Invoke-Step 'creating uninstaller in Documents' { New-Uninstaller } -Soft

    if ($script:Hibernate) {
        Write-Summary 'DORMANT is live. this machine sleeps at night and wakes on its own.'
    }
    else {
        Write-Summary 'DORMANT is live. this machine stays on with the screen off at night.'
    }
}

function Uninstall-Dormant {
    Invoke-Step 'stopping idle loop' { Stop-Loop }
    Invoke-Step 'removing scheduled tasks' { Remove-Tasks; Remove-TaskFolder }
    Invoke-Step 'removing files' { Remove-Root }
    Invoke-Step 'restoring wallpaper' { Restore-Wallpaper } -Soft
    Invoke-Step 'removing player data' { Remove-UserData } -Soft
    Invoke-Step 'removing uninstaller from Documents' { Remove-Uninstaller } -Soft

    Write-Summary 'DORMANT was removed. power settings were left as they are.'
}

Initialize-Console
Show-Banner
if ($script:UninstallMode) {
    Write-Line '  >> remove DORMANT from this machine?' White
    Write-Line '  [y]  yes, uninstall'
    Write-Line '  [n]  no, keep it'
    Write-Line
    Write-Host '  >> ' -ForegroundColor White -NoNewline
    while ($true) {
        $answer = ([string][Console]::ReadKey($true).KeyChar).ToLowerInvariant()
        if (@('y', 'n') -contains $answer) {
            Write-Host $answer -ForegroundColor White
            Write-Line
            break
        }
    }
    if ($answer -eq 'y') {
        Uninstall-Dormant
    }
    else {
        Write-Line '  :: nothing was changed.' DarkGray
    }
    Write-Line
    Write-Line '  press any key to close' DarkGray
    [void][Console]::ReadKey($true)
    if ($answer -eq 'y' -and $script:Failures -eq 0) {
        Remove-SelfLater
    }
    exit 0
}
switch (Read-Choice) {
    '1' { Install-Dormant }
    '2' { Uninstall-Dormant }
    '3' { exit 0 }
}
Write-Line
Write-Line '  press any key to close' DarkGray
[void][Console]::ReadKey($true)
exit 0
