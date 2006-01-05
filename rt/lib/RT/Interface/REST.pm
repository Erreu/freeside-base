# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
# lib/RT/Interface/REST.pm
#

package RT::Interface::REST;
use strict;
use RT;

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT);

    $VERSION = do { my @r = (q$Revision: 1.1.1.3 $ =~ /\d+/g); sprintf "%d."."%02d"x$#r, @r };

    @ISA = qw(Exporter);
    @EXPORT = qw(expand_list form_parse form_compose vpush vsplit);
}

my $field = '[a-zA-Z][a-zA-Z0-9_-]*';

sub expand_list {
    my ($list) = @_;
    my ($elt, @elts, %elts);

    foreach $elt (split /,/, $list) {
        if ($elt =~ /^(\d+)-(\d+)$/) { push @elts, ($1..$2) }
        else                         { push @elts, $elt }
    }

    @elts{@elts}=();
    return sort {$a<=>$b} keys %elts;
}

# Returns a reference to an array of parsed forms.
sub form_parse {
    my $state = 0;
    my @forms = ();
    my @lines = split /\n/, $_[0];
    my ($c, $o, $k, $e) = ("", [], {}, "");

    LINE:
    while (@lines) {
        my $line = shift @lines;

        next LINE if $line eq '';

        if ($line eq '--') {
            # We reached the end of one form. We'll ignore it if it was
            # empty, and store it otherwise, errors and all.
            if ($e || $c || @$o) {
                push @forms, [ $c, $o, $k, $e ];
                $c = ""; $o = []; $k = {}; $e = "";
            }
            $state = 0;
        }
        elsif ($state != -1) {
            if ($state == 0 && $line =~ /^#/) {
                # Read an optional block of comments (only) at the start
                # of the form.
                $state = 1;
                $c = $line;
                while (@lines && $lines[0] =~ /^#/) {
                    $c .= "\n".shift @lines;
                }
                $c .= "\n";
            }
            elsif ($state <= 1 && $line =~ /^($field):(?:\s+(.*))?$/) {
                # Read a field: value specification.
                my $f  = $1;
                my @v  = ($2 || ());

                # Read continuation lines, if any.
                while (@lines && ($lines[0] eq '' || $lines[0] =~ /^\s+/)) {
                    push @v, shift @lines;
                }
                pop @v while (@v && $v[-1] eq '');

                # Strip longest common leading indent from text.
                my ($ws, $ls) = ("");
                foreach $ls (map {/^(\s+)/} @v[1..$#v]) {
                    $ws = $ls if (!$ws || length($ls) < length($ws));
                }
                s/^$ws// foreach @v;

                push(@$o, $f) unless exists $k->{$f};
                vpush($k, $f, join("\n", @v));

                $state = 1;
            }
            elsif ($line !~ /^#/) {
                # We've found a syntax error, so we'll reconstruct the
                # form parsed thus far, and add an error marker. (>>)
                $state = -1;
                $e = form_compose([[ "", $o, $k, "" ]]);
                $e.= $line =~ /^>>/ ? "$line\n" : ">> $line\n";
            }
        }
        else {
            # We saw a syntax error earlier, so we'll accumulate the
            # contents of this form until the end.
            $e .= "$line\n";
        }
    }
    push(@forms, [ $c, $o, $k, $e ]) if ($e || $c || @$o);

    my $l;
    foreach $l (keys %$k) {
        $k->{$l} = vsplit($k->{$l}) if (ref $k->{$l} eq 'ARRAY');
    }

    return \@forms;
}

# Returns text representing a set of forms.
sub form_compose {
    my ($forms) = @_;
    my (@text, $form);

    foreach $form (@$forms) {
        my ($c, $o, $k, $e) = @$form;
        my $text = "";

        if ($c) {
            $c =~ s/\n*$/\n/;
            $text = "$c\n";
        }
        if ($e) {
            $text .= $e;
        }
        elsif ($o) {
            my (@lines, $key);

            foreach $key (@$o) {
                my ($line, $sp, $v);
                my @values = (ref $k->{$key} eq 'ARRAY') ?
                               @{ $k->{$key} } :
                                  $k->{$key};

                $sp = " "x(length("$key: "));
                $sp = " "x4 if length($sp) > 16;

                foreach $v (@values) {
                    if ($v =~ /\n/) {
                        $v =~ s/^/$sp/gm;
                        $v =~ s/^$sp//;

                        if ($line) {
                            push @lines, "$line\n\n";
                            $line = "";
                        }
                        elsif (@lines && $lines[-1] !~ /\n\n$/) {
                            $lines[-1] .= "\n";
                        }
                        push @lines, "$key: $v\n\n";
                    }
                    elsif ($line &&
                           length($line)+length($v)-rindex($line, "\n") >= 70)
                    {
                        $line .= ",\n$sp$v";
                    }
                    else {
                        $line = $line ? "$line, $v" : "$key: $v";
                    }
                }

                $line = "$key:" unless @values;
                if ($line) {
                    if ($line =~ /\n/) {
                        if (@lines && $lines[-1] !~ /\n\n$/) {
                            $lines[-1] .= "\n";
                        }
                        $line .= "\n";
                    }
                    push @lines, "$line\n";
                }
            }

            $text .= join "", @lines;
        }
        else {
            chomp $text;
        }
        push @text, $text;
    }

    return join "\n--\n\n", @text;
}

# Add a value to a (possibly multi-valued) hash key.
sub vpush {
    my ($hash, $key, $val) = @_;
    my @val = ref $val eq 'ARRAY' ? @$val : $val;

    if (exists $hash->{$key}) {
        unless (ref $hash->{$key} eq 'ARRAY') {
            my @v = $hash->{$key} ne '' ? $hash->{$key} : ();
            $hash->{$key} = \@v;
        }
        push @{ $hash->{$key} }, @val;
    }
    else {
        $hash->{$key} = $val;
    }
}

# "Normalise" a hash key that's known to be multi-valued.
sub vsplit {
    my ($val) = @_;
    my ($line, $word, @words);

    foreach $line (map {split /\n/} (ref $val eq 'ARRAY') ? @$val : $val)
    {
        # XXX: This should become a real parser, � la Text::ParseWords.
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        push @words, split /\s*,\s*/, $line;
    }

    return \@words;
}

1;

=head1 NAME

  RT::Interface::REST - helper functions for the REST interface.

=head1 SYNOPSIS

  Only the REST should use this module.
