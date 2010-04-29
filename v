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
  :wc    => 'wc',
  :cat   => 'cat',
  :bash  => 'bash',
  :zsh   => 'zsh',
}

$nkfopt = '-w'
$nkfrec = '--run-nkf'
$bin[:nkf] = "#{$bin[:ruby]} #{$0} #{$nkfrec}"

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
  return `#{$bin[:which]} #{name} | #{$bin[:wc]} -l`.to_i != 0 ? name : nil
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
  :escape => rtp.map{|v| "#{v}/#{$vimfile[:escape]}"}.find{|v| File.exist?(v)},
  :verbose => false,
}
argv = GetOpt.new($*, %w'
  vim
  s|syntax=s
  k|nkf
  e|escape
  v|verbose
  h|help
', dargv)
argv[:psub] = path_exist?($bin[:bash]) || path_exist?($bin[:zsh])
argv[:shell] = ENV['SHELL'] || argv[:psub]

if argv[:help]
  dargv.each{|k,v| dargv[k] = v ? 'on' : 'off'}
  puts <<"EOM"
Usage: #{File.basename($0)} [-s syntax] [-kevh] [--] file...
Options:
  -s, --syntax   Set syntax.
  -k, --nkf      Use nkf (default: #{dargv[:nkf]}).
  -e, --escape   Manipulate ANSI escape sequences (default: #{dargv[:escape]}).
  -v, --verbose  Show extra information (default: #{dargv[:verbose]}).
  -h, --help     Show help.
EOM
  exit
end

cmd = []
vimcmd = [ $bin[:vim] ]
vimopt =
  [
   '--cmd',
   'let no_plugin_maps = 1',
   '-c',
   "runtime! #{$vimfile[:less]}",
  ] # default options from less.sh

# ANSI escape sequence
vimopt = [ '--cmd', "runtime #{$vimfile[:escape]}" ] + vimopt if argv[:escape]

# set syntax explicitly
vimopt += [ '-c', "set syntax=#{argv[:syntax]}" ] if argv[:syntax]

if argv.args.length == 0  # read from standard input
  input = argv[:nkf] ? "=(#{$bin[:nkf]})" : "=(#{$bin[:cat]})"
  vimcmd = [ "#{$bin[:ruby]} #{$0} #{$vimrec}" ] if argv[:psub]
  argv[:stdin] = !argv[:psub]
else                      # read from file
  files = argv.args + argv.rest
  files.reject! do |f|
    warn_if(!File.exist?(f), "#{f}: no such file or directory") ||
    warn_if(File.directory?(f), "#{f} is a directory")
  end # exclude non-existing files
  exit(1) if files.size < 1 # no file to read

  input = files.map{|f| GetOpt.escape(f)}.join(' ')
  if !argv[:psub] && argv[:nkf]
    cmd.unshift("#{$bin[:cat]} #{input}")
    argv[:stdin] = true
  elsif argv[:nkf]
    ftype = [ '--cmd', 'aug f' ] # new autogroup
    i=0
    files = files.map do |f|
      i += 1
      ftype +=
        [ '--cmd',
          "au f BufReadPost <buffer=#{i}> " + # add autocmd
          [
           "file #{f}",       # set filename of buffer i
           'filetype detect', # auto detect filetype
           'set buftype+=nofile',
           "au! f BufReadPost <buffer=#{i}>", # remove autocmd
          ].join(' | ')
        ]
      "=(#{$bin[:nkf]} #{GetOpt.escape(f)})"
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
  warn("command: #{cmd.join(' | ')}") if argv[:verbose]
  system(cmd.join(' | '))
else
  warn("command: #{cmd.join(' | ')}") if argv[:verbose]
  system(argv[:shell], '-c', cmd.join(' | '))
end
