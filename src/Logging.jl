module Logging

using Compat

import Base: show

export debug, info, warn, err, critical, log,
       @debug, @info, @warn, @err, @error, @critical, @log,
       Logger,
       LogLevel, DEBUG, INFO, WARNING, ERROR, CRITICAL, OFF

if VERSION < v"0.4.0-dev+3587"
    include("enum.jl")
end

@enum LogLevel DEBUG INFO WARNING ERROR CRITICAL OFF

try
    DEBUG < CRITICAL
catch
    Base.isless(x::LogLevel, y::LogLevel) = isless(x.val, y.val)
end

const OLD_CONVERSION_PATTERN     = "%d{%d-%b %H:%M:%S}:%p:%t:%m%n"
const BASIC_CONVERSION_PATTERN   = "%R %p %c %x: %m%n"
const DEFAULT_CONVERSION_PATTERN = "%m%n"
const SIMPLE_CONVERSION_PATTERN  = "%p - %m%n"
const TTCC_CONVERSION_PATTERN    = "%r [%t] %p %c %x - %m%n"

type Logger
    name::String
    level::LogLevel
    output::IO
    parent::Logger
    pattern::String
    timestamp::Uint64

    Logger(name::String, level::LogLevel, output::IO, parent::Logger, pattern::String) =
        new(name, level, output, parent, pattern, time_ns())
    Logger(name::String, level::LogLevel, output::IO, parent::Logger) =
        Logger(name, level, output, parent, DEFAULT_CONVERSION_PATTERN)
    function Logger(name::String, level::LogLevel, output::IO)
        x = new()
        x.name = name
        x.level=level
        x.output=output
        x.parent=x
        x.pattern=DEFAULT_CONVERSION_PATTERN
        x.timestamp = time_ns()
        x
    end
end

show(io::IO, logger::Logger) = print(io, "Logger(", join([logger.name, 
                                                          logger.level, 
                                                          logger.output,
                                                          logger.parent.name], ","), ")")

const _root = Logger("root", WARNING, STDERR)
Logger(name::String;args...) = configure(Logger(name, WARNING, STDERR, _root); args...)
Logger() = Logger("logger")

include("formater.jl")

for (fn,lvl,clr) in ((:debug,    DEBUG,    :cyan),
                     (:info,     INFO,     :blue),
                     (:warn,     WARNING,  :magenta),
                     (:err,      ERROR,    :red),
                     (:critical, CRITICAL, :red))

    @eval function $fn(logger::Logger, msg...)
        if $lvl >= logger.level
            logstring = formatPattern(logger, $lvl, msg...)
            if isa(logger.output, Base.TTY)
                Base.print_with_color($(Expr(:quote, clr)), logger.output, logstring )
            else
                print(logger.output, logstring)
                flush(logger.output)
            end
        end
    end

    @eval $fn(msg...) = $fn(_root, msg...)

end

function configure(logger=_root; args...)
    for (tag, val) in args
        if tag == :parent
            logger.parent = parent = val::Logger
            logger.level = parent.level
            logger.output = parent.output
        end
    end

    for (tag, val) in args
        tag == :io            ? (logger.output = val::IO) :
        tag == :output        ? (logger.output = val::IO) :
        tag == :filename      ? (logger.output = open(val, "a")) :
        tag == :level         ? (logger.level  = val::LogLevel) :
        tag == :format        ? (logger.pattern = val) :
        tag == :override_info ? nothing :  # handled below
        tag == :parent        ? nothing :  # handled above
                                (Base.error("Logging: unknown configure argument \"$tag\""))
    end

    logger
end

override_info(;args...) = (:override_info, true) in args

macro configure(args...)
    _args = gensym()
    quote
        logger = Logging.configure($(args...))
        if Logging.override_info($(args...))
            function Base.info(msg::String...)
                Logging.info(Logging._root, msg...)
            end
        end
        include(joinpath(Pkg.dir("Logging"), "src", "logging_macros.jl"))
        logger
    end
end

end # module

