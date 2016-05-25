=head1 NAME

  RT::Search::UnrepliedTickets

=head1 SYNOPSIS

=head1 DESCRIPTION

Find all unresolved tickets owned by the current user where the last correspondence
from a requestor (or ticket creation) is more recent than the last
correspondence from a non-requestor (if there is any).

=head1 METHODS

=cut

package RT::Search::UnrepliedTickets;

use strict;
use warnings;
use base qw(RT::Search);


sub Describe  {
  my $self = shift;
  return ($self->loc("Tickets awaiting a reply"));
}

sub Prepare  {
  my $self = shift;

  my $TicketsObj = $self->TicketsObj;
  $TicketsObj->Limit(
    FIELD => 'Owner',
    VALUE => $TicketsObj->CurrentUser->id
  );
  $TicketsObj->Limit(
    FIELD => 'Status',
    OPERATOR => '!=',
    VALUE => 'resolved'
  );
  my $txn_alias = $TicketsObj->JoinTransactions;
  $TicketsObj->Limit(
    ALIAS => $txn_alias,
    FIELD => 'Created',
    OPERATOR => '>',
    VALUE => 'COALESCE(main.Told,\'1970-01-01\')',
    QUOTEVALUE => 0,
  );
  $TicketsObj->Limit(
    ALIAS => $txn_alias,
    FIELD => 'Type',
    OPERATOR => 'IN',
    VALUE => [ 'Correspond', 'Create' ],
  );

  return(1);
}

RT::Base->_ImportOverlays();

1;
