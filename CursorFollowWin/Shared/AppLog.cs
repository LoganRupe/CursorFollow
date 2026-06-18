using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace CursorFollowWin;

/// <summary>
/// Central logging access. Uses Microsoft.Extensions.Logging with a lightweight daily-rolling
/// file sink under <c>%LocalAppData%\CursorFollowWin\Logs</c>. Category loggers match the
/// architecture so log lines name the component that produced them. Loggers default to a
/// no-op until <see cref="Initialize"/> runs, so early or test calls never throw.
/// </summary>
public static class AppLog
{
    // Mutable so the Settings "Log level" choice can raise or lower verbosity at runtime. Read by
    // every FileLogger via IsEnabled; defaults to Information so startup logs (emitted before
    // settings load) are captured.
    private static volatile int _minimumLevel = (int)LogLevel.Information;

    private static ILoggerFactory? _factory;

    public static ILogger App { get; private set; } = NullLogger.Instance;
    public static ILogger Capture { get; private set; } = NullLogger.Instance;
    public static ILogger Output { get; private set; } = NullLogger.Instance;
    public static ILogger WindowTracker { get; private set; } = NullLogger.Instance;
    public static ILogger Hotkeys { get; private set; } = NullLogger.Instance;
    public static ILogger Startup { get; private set; } = NullLogger.Instance;

    internal static LogLevel MinimumLevel => (LogLevel)_minimumLevel;

    /// <summary>Directory holding the daily-rolling log files.</summary>
    public static string LogDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CursorFollowWin",
        "Logs");

    /// <summary>Path to today's log file (may not exist yet if nothing has been logged).</summary>
    public static string CurrentLogFilePath =>
        Path.Combine(LogDirectory, $"cursorfollowwin-{DateTime.Now:yyyyMMdd}.log");

    public static void Initialize()
    {
        if (_factory is not null)
        {
            return;
        }

        _factory = LoggerFactory.Create(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Trace);
            builder.AddProvider(new FileLoggerProvider(LogDirectory));
        });

        App = _factory.CreateLogger("App");
        Capture = _factory.CreateLogger("Capture");
        Output = _factory.CreateLogger("Output");
        WindowTracker = _factory.CreateLogger("WindowTracker");
        Hotkeys = _factory.CreateLogger("Hotkeys");
        Startup = _factory.CreateLogger("Startup");
    }

    /// <summary>
    /// Applies the user's log-level choice (the Settings strings "None", "Errors only", "Standard",
    /// "Verbose"). Anything else falls back to Information.
    /// </summary>
    public static void ApplyLevel(string? level)
    {
        _minimumLevel = (int)(level switch
        {
            "None" => LogLevel.None,
            "Errors only" => LogLevel.Error,
            "Verbose" => LogLevel.Debug,
            _ => LogLevel.Information, // Standard
        });
    }

    public static void Shutdown()
    {
        _factory?.Dispose();
        _factory = null;
    }
}

internal sealed class FileLoggerProvider : ILoggerProvider
{
    private readonly string _directory;
    private readonly object _gate = new();
    private bool _directoryReady;

    public FileLoggerProvider(string directory)
    {
        _directory = directory;
    }

    public ILogger CreateLogger(string categoryName) => new FileLogger(categoryName, this);

    public void Dispose()
    {
    }

    internal void Write(string line)
    {
        try
        {
            lock (_gate)
            {
                if (!_directoryReady)
                {
                    Directory.CreateDirectory(_directory);
                    _directoryReady = true;
                }

                File.AppendAllText(CurrentFilePath(), line + Environment.NewLine);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Logging must never take down the app; drop the line if the sink is unavailable.
        }
    }

    private string CurrentFilePath() =>
        Path.Combine(_directory, $"cursorfollowwin-{DateTime.Now:yyyyMMdd}.log");
}

internal sealed class FileLogger : ILogger
{
    private readonly string _category;
    private readonly FileLoggerProvider _provider;

    public FileLogger(string category, FileLoggerProvider provider)
    {
        _category = category;
        _provider = provider;
    }

    public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;

    public bool IsEnabled(LogLevel logLevel) => logLevel >= AppLog.MinimumLevel;

    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel))
        {
            return;
        }

        var message = formatter(state, exception);
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{Abbreviate(logLevel)}] {_category}: {message}";
        if (exception is not null)
        {
            line += Environment.NewLine + exception;
        }

        _provider.Write(line);
    }

    private static string Abbreviate(LogLevel level) => level switch
    {
        LogLevel.Trace => "TRC",
        LogLevel.Debug => "DBG",
        LogLevel.Information => "INF",
        LogLevel.Warning => "WRN",
        LogLevel.Error => "ERR",
        LogLevel.Critical => "CRT",
        _ => "???",
    };

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();

        public void Dispose()
        {
        }
    }
}
