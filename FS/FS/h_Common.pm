package FS::h_Common;

use strict;
use FS::Record qw(dbdef);
use Carp qw(confess);

=head1 NAME

FS::h_Common - History table "mixin" common base class

=head1 SYNOPSIS

package FS::h_tablename;
@ISA = qw( FS::h_Common FS::tablename ); 

sub table { 'h_table_name'; }

sub insert { return "can't insert history records manually"; }
sub delete { return "can't delete history records"; }
sub replace { return "can't modify history records"; }

=head1 DESCRIPTION

FS::h_Common is intended as a "mixin" base class for history table classes to
inherit from.

=head1 METHODS

=over 4

=item sql_h_search END_TIMESTAMP [ START_TIMESTAMP ] 

Returns an a list consisting of the "SELECT" and "EXTRA_SQL" SQL fragments to
search for the appropriate history records created before END_TIMESTAMP
and (optionally) not cancelled before START_TIMESTAMP.

=cut

sub sql_h_search {
  my( $self, $end ) = ( shift, shift );

  my $table = $self->table;
  my $real_table = ($table =~ /^h_(.*)$/) ? $1 : $table;
  my $pkey = dbdef->table($real_table)->primary_key
    or die "can't (yet) search history table $real_table without a primary key";

  unless ($end) {
    confess 'Called sql_h_search without END_TIMESTAMP';
  }

  my $notcancelled = '';
  if ( scalar(@_) && $_[0] ) {
    $notcancelled = "AND 0 = ( SELECT COUNT(*) FROM $table as notdel
                                WHERE notdel.$pkey = maintable.$pkey
                                AND notdel.history_action = 'delete'
                                AND notdel.history_date > maintable.history_date
                                AND notdel.history_date <= $_[0]
                             )";
  }

  (
    "DISTINCT ON ( $pkey ) *",

    "AND history_date <= $end
     AND (    history_action = 'insert'
           OR history_action = 'replace_new'
         )
     $notcancelled
     ORDER BY $pkey ASC, history_date DESC",

     '',

     'AS maintable',
  );

}

=item sql_h_searchs END_TIMESTAMP [ START_TIMESTAMP ] 

Like sql_h_search, but limited to the single most recent record (before
END_TIMESTAMP)

=cut

sub sql_h_searchs {
  my $self = shift;
  my($select, $where, $cacheobj, $as) = $self->sql_h_search(@_);
  $where .= ' LIMIT 1';
  ($select, $where, $cacheobj, $as);
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation

=cut

1;

