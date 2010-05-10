#! /usr/bin/env ruby
$:.unshift(File.join(File.dirname($0), 'lib'))
begin
  require 'rubygems'
rescue LoadError
end
require 'getopt'
require 'nkf'

$bin = {
  :ruby  => 'ruby',
  :vim   => 'vim',
  :sh    => 'sh',
  :echo  => 'echo',
  :test  => 'test',
  :which => '/usr/bin/which',
  :cat   => 'cat',
  :bash  => 'bash',
  :zsh   => 'zsh',
  :p7z    => '7z',
}

$archive =
  [
   '7z', 'zip', 'cab', 'arj', 'gz', 'bz2', 'tar', 'cpio', 'rpm', 'deb', 'rar',
  ]

$nkfopt = '-w'
$nkfopt = '-j' if ENV['LANG'] =~ /\.(?:jis|iso[-_]?2022[-_]?jp)/i
$nkfopt = '-e' if ENV['LANG'] =~ /\.euc[-_]?jp/i
$nkfopt = '-s' if ENV['LANG'] =~ /\.s(?:hift)?[-_]?jis/i
$nkfopt = '-w16' if ENV['LANG'] =~ /\.utf[-_]?16/i

$nkfrec = '--run-nkf'
$bin[:nkf] = "#{$bin[:ruby]} #{$0} #{$nkfrec}"

$nkfguess = '--run-nkf-guess'
$bin[:nkfguess] = "#{$bin[:ruby]} #{$0} #{$nkfguess}"

$p7zrec = '--run-7z'
$bin[:p7zrec] = "#{$bin[:ruby]} #{$0} #{$p7zrec}"

$vimrec = '--run-vim'

$vimfile = {
  :less   => 'macros/less.vim',
  :escape => 'ansi_escape.vim',
}

#### run nkf

if $*[0] == $nkfrec
  $*.shift
  print(NKF.nkf($nkfopt, ARGF.read))
  exit
end

#### run nkf guess

if $*[0] == $nkfguess
  $*.shift
  print(NKF.guess(ARGF.read))
  exit
end

$fenc = {
  NKF::JIS     => 'iso-2022-jp',
  NKF::EUC     => 'euc-jp',
  NKF::SJIS    => 'sjis',
  NKF::BINARY  => nil,
  NKF::UNKNOWN => nil,
  NKF::ASCII   => 'utf-8',
  NKF::UTF8    => 'utf-8',
  NKF::UTF16   => 'utf-16',
}

### run 7z

if $*[0] == $p7zrec
  $*.shift
  argv = GetOpt.new($*)
  print(`#{$bin[:sh]} -c '</dev/tty #{$bin[:p7z]} e -so #{argv}' 2>/dev/null`)
  exit
end

#### run vim

if $*[0] == $vimrec # close stdin before running vim
  $*.shift
  argv = GetOpt.new($*)
  system("#{$bin[:sh]} -c '</dev/tty #{$bin[:vim]} #{argv}'")
  exit
end

#### do nothing

unless system("#{$bin[:test]} -t 1") # output is not a terminal
  args = $*.map{|v| GetOpt.escape(v)}.join(' ')
  system("#{$bin[:cat]} #{args}")
  exit
end

#### main

def path_exist?(name) # search path
  path = `#{$bin[:which]} #{name}`.strip
  return !path.empty? && system("test -x \"#{path}\"") && path
end

def warn_if(cond, msg)
  return cond && (warn(msg) || true)
end

# vim runtimepath
rtpcmd =
  [
   "#{$bin[:vim]} -e -s",
   "--cmd 'exe \"silent !#{$bin[:echo]} \" . &runtimepath'",
   "--cmd q",
  ].join(' ')
rtp = `#{rtpcmd}`
rtp = rtp.strip.split(',')

dargv = { # default values
  :nkf => true,
  :extract => path_exist?($bin[:p7z]),
  :escape => rtp.map{|v| "#{v}/#{$vimfile[:escape]}"}.find{|v| File.exist?(v)},
  :verbose => false,
  :psub => path_exist?($bin[:bash]) || path_exist?($bin[:zsh]),
}
dargv[:extract] = dargv[:psub]
argv = GetOpt.new($*, %w'
  psub
  s|syntax=s
  k|nkf
  x|extract
  e|escape
  v|verbose
  h|help
', dargv)
argv[:shell] = ENV['SHELL'] || argv[:psub]

if argv[:help]
  dargv.each{|k,v| dargv[k] = v ? 'on' : 'off'}
  puts <<"EOM"
Usage: #{File.basename($0)} [-s syntax] [-kevh] [--] file...
Options:
  -s, --syntax   Set syntax.
  -k, --nkf      Use nkf (default: #{dargv[:nkf]}).
  -x, --extract  Automatically extract archive files (default: #{dargv[:extract]}).
  -e, --escape   Manipulate ANSI escape sequences (default: #{dargv[:escape]}).
  -v, --verbose  Show extra information (default: #{dargv[:verbose]}).
  -h, --help     Show help.
EOM
  exit
end

files = argv.args + argv.rest
rejected = false
files.reject! do |f|
  r = warn_if(!File.exist?(f), "#{f}: no such file or directory")
  r ||= warn_if(File.directory?(f), "#{f} is a directory")
  rejected ||= r
  r
end # exclude non-existing files

if files.size < 1 && system("#{$bin[:test]} -t 0")
  msg = "Missing filename (\"#{File.basename($0)} --help\" for help)"
  puts(msg) unless rejected
  exit
end # no input

cmd = []
vimcmd = [ $bin[:vim] ]
vimopt =
  [
   '--cmd',
   'let no_plugin_maps = 1',
   '--cmd',
   "runtime! #{$vimfile[:less]}",
  ] # default options from less.sh

# ANSI escape sequence
vimopt += [ '-c', "runtime #{$vimfile[:escape]}" ] if argv[:escape]

# set syntax explicitly
vimopt += [ '-c', "set syntax=#{argv[:syntax]}" ] if argv[:syntax]

if files.length == 0  # read from standard input
  input = argv[:nkf] ? "<(#{$bin[:nkf]})" : "<(#{$bin[:cat]})"
  vimcmd = [ "#{$bin[:ruby]} #{$0} #{$vimrec}" ] if argv[:psub]
  argv[:stdin] = !argv[:psub]
else                      # read from file
  if !argv[:psub] && argv[:nkf]
    input = files.map{|f| GetOpt.escape(f)}.join(' ')
    cmd.unshift("#{$bin[:cat]} #{input}")
    argv[:stdin] = true
  else
    ftype = [ '--cmd', 'aug f' ] # new autogroup
    i=0
    files = files.map do |f|
      detect = f
      file = GetOpt.escape(f)
      fenc = nil

      translators = []
      extractors = []
      translators << $bin[:nkf] if argv[:nkf]
      if argv[:extract] && $archive.include?((File.extname(f)||'')[1..-1])
        extractors << $bin[:p7zrec]
        detect = f[0...-(File.extname(f).length)]
      end

      i += 1
      filters = extractors + translators
      if !filters.empty?
        if argv[:nkf]
          g = extractors + [ $bin[:nkfguess] ]
          fenc = $fenc[`#{[ g[0]+' '+file, *g[1..-1] ].join('|')}`.to_i]
        end

        ftype +=
          [ '--cmd',
            "au f BufReadPost <buffer=#{i}> " + # add autocmd
            [
             "file #{detect}",  # set filename of buffer i
             'filetype detect', # auto detect filetype
             detect != f && "file #{f}",
             fenc && 'set modifiable',
             fenc && "setl fenc=#{fenc}",
             fenc && 'set nomodifiable',
             "au! f BufReadPost <buffer=#{i}>", # remove autocmd
            ].reject{|s| !s}.join('|')
          ]
         file = "<(#{[ filters[0]+' '+file, *filters[1..-1] ].join('|')})"
      end

      file
    end
    vimopt = ftype + vimopt
    input = files.join(' ')
  end
end

if argv[:stdin]
  input = '-'
  cmd << "#{$bin[:nkf]} #{$nkfopt}" if argv[:nkf]
end

vimcmd += vimopt.map{|v| GetOpt.escape(v)}
vimcmd << input
cmd << vimcmd.join(' ')

if argv[:stdin]
  warn("command: #{cmd.join('|')}") if argv[:verbose]
  system(cmd.join('|'))
else
  warn("command: #{cmd.join('|')}") if argv[:verbose]
  system(argv[:shell], '-c', cmd.join('|'))
end
