#!/usr/bin/env perl
# Copyright (c) 2010, 2013, 2016 Andreas F. Borchert
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Changes by Arves100:
	# 1. Added ability to use different gcc names (usefull for crosscompiling)
	# 2. Added ability to change the output file (no longer need to replace Makefile, usefull when using gitignore)

use strict;
use warnings;
use IO::File;
use IO::Pipe;

my $cmdname = $0; $cmdname =~ s{.*/}{};
my $usage = "Usage: $cmdname {-p prefix} {-o output} [-gcc gcc_file] [gcc or g++ options] {source}\n";
my @prefix;
my $makefile;
my @gcc_file;
while (@ARGV > 1 && $ARGV[0] eq "-p") {
   push(@prefix, $ARGV[1]);
   shift; shift;
}
while (@ARGV > 1 && $ARGV[0] eq "-o") {
   $makefile = $ARGV[1];
   shift; shift;
}
while (@ARGV > 1 && $ARGV[0] eq "--gcc") {
	push(@gcc_file, $ARGV[1]);
	shift; shift;
}
die $usage if @ARGV == 0;

#foreach my $candidate (qw(makefile Makefile)) {
#   next unless -f $candidate;
#   $makefile = $candidate;
#   last;
#}
die "$cmdname: no makefile found in the current directory\n"
   unless defined $makefile;

my $contents = scan_makefile($makefile);
my $dependencies = execute_gcc(@ARGV);
gen_makefile($makefile, $contents, $dependencies);

sub scan_makefile {
   my ($infile) = @_;
   my $in = new IO::File $infile
      or die "$cmdname: unable to open $infile for reading: $!\n";
   my $contents = "";
   while (<$in>) {
      last if m{^# DO NOT DELETE$};
      $contents .= $_;
   }
   $in->close;
   $contents .= "# DO NOT DELETE\n";
   return $contents;
}

sub gen_makefile {
   my ($outfile, $contents, $dependencies) = @_;
   my $tmpfile = $outfile . ".TMP";
   unlink ($tmpfile) if -f $tmpfile;
   my $out = new IO::File $tmpfile, O_WRONLY|O_CREAT|O_EXCL
      or die "$cmdname: unable to create $tmpfile: $!\n";
   print $out $contents or die "$cmdname: write error on $tmpfile: $!\n";
   print $out $dependencies or die "$cmdname: write error on $tmpfile: $!\n";
   $out->close or die "$cmdname: write error on $tmpfile: $!\n";
   rename($tmpfile, $outfile)
      or die "$cmdname: unable to rename $tmpfile to $outfile: $!\n";
}

sub execute_gcc {
   my (@options) = @_;
   my @cmd = (@gcc_file, "-MM", @options);
   my $cmd = join(" ", @cmd);
   my $pipe = new IO::Pipe;
   my $pid = fork();
   die "$cmdname: unable to fork: $!\n" unless defined $pid;
   if ($pid == 0) {
      $pipe->writer;
      my $fd = $pipe->fileno;
      open(STDOUT, ">&=$fd");
      open(STDERR, ">&=$fd");
      close(STDIN);
      exec(@cmd);
      die "$cmdname: unable to invoke $cmd\n";
   }
   $pipe->reader;
   my $msg = ""; my $lines;
   my $flush_line = sub {
      if (defined $lines && $lines ne "") {
	 foreach my $prefix (@prefix) {
	    $msg .= $prefix . $lines;
	 }
	 $lines = "";
      }
   };
   while (<$pipe>) {
      my $line = $_;
      if (@prefix == 0) {
	 $msg .= $line;
      } else {
	 if ($line !~ m{^\s}) {
	    &$flush_line();
	 }
	 $lines .= $line;
      }
   }
   &$flush_line();
   $pipe->close;
   waitpid($pid, 0) >= 0 or die "$cmdname: unable to wait for $pid: $!\n";
   if ($?) {
      print STDERR "$cmdname: $cmd failed:\n";
      print STDERR $msg;
      die "$cmdname: $makefile was not updated.\n";
   }
   return $msg;
}

__END__

=head1 NAME

gcc-makedepend -- gcc-based makedepend clone

=head1 SYNOPSIS

B<gcc-makedepend> {B<-p> I<prefix>} [I<gcc or g++ options>] {I<source>}

=head1 DESCRIPTION

B<gcc-makedepend> works like B<makedepend> but is based upon the
B<-MM> option of B<gcc>. This has the advantage that all standard
include directories are considered including those which are not
known to B<makedepend>.

B<gcc-makedepend> updates either F<makefile> or F<Makefile>,
whatever is found first, by adding or updating the actual
list of header file dependencies of all given sources.

Like B<makedepend>, B<gcc-makedepend> generates and honors the

   # DO NOT DELETE

comment line within the to-be-updated makefile, i.e. if this
line is found, all makefile lines behind it are considered to
be a to-be-updated list of dependencies, and, if this line
is not yet present, it will be generated together with the
newly generated dependencies. In consequence, neither this
line nor any makefile contents beyond this line should be touched
except by B<gcc-makedepend>.

The option B<-p> allows to specify a prefix that will be
prepended to all dependency lines output by B<gcc>. This
is useful if the target directory for output files is not
the current directory. If multiple prefix options are given,
each output line by B<gcc> will be repeated for each prefix
with the individual prefix applied.

=head1 HISTORY

This is not the first attempt to develop a gcc-based replacement of
B<makedepend>. Another solution named makedependgcc was previously
developed by David Coppit which, however, diverts from the original
B<makedepend> invocation line, provides no error recovery with the danger
of corrupting the to-be-updated makefile, and which does not come with
a manual page. B<makedependgcc> gave, however, the insight that the
B<-M> option of B<gcc> can be used to avoid B<makedepend>.

=head1 AUTHOR

Andreas F. Borchert

=cut
