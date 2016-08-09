#!/usr/bin/perl

use warnings;
use strict;

#========================================================================#

=pod

=head1 NAME

gcc-reg-graph - Basic block graph along with register use/def info.

=head1 OPTIONS

B<gcc-reg-graph> [-h|--help] FUNCTION-NAME INPUT-FILE

=head1 SYNOPSIS

Read an input file produced by GCC with the I<--fdump-rtl-all> flag, the
specific input file used is the '*.ira' file.

The FUNCTION-NAME is the name of the function that you're interested in.

The output, produced to stdout, is a GraphViz style graph describing the
basic block layout for the function.  Each node is annotated with the
register use/def information for that block.

=cut

#========================================================================#

use lib "$ENV{HOME}/lib";
use GiveHelp qw/usage/;         # Allow -h or --help command line options.
use Carp;
use Carp::Assert;
use boolean;

#========================================================================#

my $function_name = shift;
my $input_filename = shift;

open my $in, $input_filename
  or croak ("failed to open '$input_filename': $!");

my $in_function = false;
my $current_block = undef;
my @all_blocks;
my $first_block = undef;
while (<$in>)
{
  if (m/^;; Function (\S+) /)
  {
    $in_function = ($1 eq $function_name);
    next;
  }

  next unless $in_function;

  if (m/^;; basic block (\d+),/)
  {
    # Start of new block.
    my $num = $1;
    $current_block = {-number => $num,
                      -reg_in => undef,
                      -reg_use => undef,
                      -reg_def => undef,
                      -reg_out => undef,
                      -successor => undef,
                      -printed => false,
                      -is_exit => false,
                      -is_entry => false};
    if (not (defined ($first_block)))
    {
      $first_block = $current_block;
      $first_block->{-is_entry} = true;
    }
    if (defined ($all_blocks [$num]))
    {
      croak ("found duplicate basic block $num");
    }
    $all_blocks [$num] = $current_block;
  }

  next unless (defined ($current_block));

  if (defined ($current_block->{-successor}))
  {
    if (m/^;;\s+(\d+)/)
    {
      push @{$current_block->{-successor}}, $1;
      next;
    }
    elsif (not (m/^;; lr /))
    {
      croak ("found unexpected line while scanning successors ".
               "in basic block ".$current_block->{-number});
    }
  }

  if (m/^;; lr  (in|use|def|out)\s+(.*)$/)
  {
    my ($type, $value) = ($1, $2);
    my $key = "-reg_".$type;
    if (defined ($current_block->{$key}))
    {
      croak ("found many instances of 'lr $type' in basic block ".
               $current_block->{-number});
    }
    $current_block->{$key} = $value;

    if ($type eq "out")
    {
      $current_block = undef;
    }
    next;
  }

  if (m/^;;  succ:/)
  {
    if (defined ($current_block->{-successor}))
    {
      croak ("multiple successor lists found for basic block "
               .$current_block->{-number});
    }
    $current_block->{-successor} = [];

    if (m/^;;  succ:\s+(\d+)/)
    {
      push @{$current_block->{-successor}}, $1;
    }
    else
    {
      $current_block->{-is_exit} = true;
    }
    next;
  }
}

close $in
  or croak ("failed to close '$input_filename': $!");

print_graph ($first_block, \@all_blocks);

exit (0);

#========================================================================#

=pod

=head1 METHODS

The following methods are defined in this script.

=over 4

=cut

#========================================================================#

=pod

=item B<count_regs>

Currently undocumented.

=cut

sub count_regs {
  my $string = shift;

  my @regs = split /\s+/, $string;
  @regs = grep {not m/[][]/} @regs;
  return scalar (@regs);
}

#========================================================================#

=pod

=item B<block_label>

Currently undocumented.

=cut

sub block_label {
  my $block = shift;

  return ("Block #".$block->{-number}."\\n".
            "live-in=".count_regs ($block->{-reg_in})."\\n".
            "defined=".count_regs ($block->{-reg_def})."\\n".
            "used=".count_regs ($block->{-reg_use})."\\n".
            "live-out=".count_regs ($block->{-reg_out}));
}

#========================================================================#

=pod

=item B<print_graph>

Currently undocumented.

=cut

sub print_graph {
  my $first_block = shift;
  my $blocks = shift;

  print "digraph G {\n";

  my @todo = ($first_block->{-number});
  print "  ENTRY -> block_".$first_block->{-number}."\n";

  while (@todo)
  {
    my $number = shift (@todo);
    my $block = $blocks->[$number];

    next if ($block->{-printed});
    $block->{-printed} = true;

    if ($block->{-is_exit})
    {
      print "  block_".$number." -> EXIT\n";
    }

    if ((not (defined ($block->{-successor})))
          or (ref ($block->{-successor}) ne 'ARRAY'))
    {
      croak ("basic block $number missing successor list");
    }
    foreach my $s (@{$block->{-successor}})
    {
      push @todo, $s;

      print "  block_".$number." -> block_".$s."\n";
    }

    my $label = block_label ($block);
    print "  block_".$number." [ label=\"".$label."\"]\n"
  }

  print "}\n";
}

#========================================================================#

=pod

=back

=head1 AUTHOR

Andrew Burgess, 03 Aug 2016

=cut
