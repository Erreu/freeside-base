package FS::cust_credit_refund;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearch qsearchs dbh );
#use FS::UID qw(getotaker);
use FS::cust_credit;
use FS::cust_refund;

@ISA = qw( FS::Record );

=head1 NAME

FS::cust_credit_refund - Object methods for cust_bill_pay records

=head1 SYNOPSIS 

  use FS::cust_credit_refund;

  $record = new FS::cust_credit_refund \%hash;
  $record = new FS::cust_credit_refund { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::cust_credit_refund represents the application of a refund to a specific
credit.  FS::cust_credit_refund inherits from FS::Record.  The following fields
are currently supported:

=over 4

=item creditrefundnum - primary key (assigned automatically)

=item crednum - Credit (see L<FS::cust_credit>)

=item refundnum - Refund (see L<FS::cust_refund>)

=item amount - Amount of the refund to apply to the specific credit.

=item _date - specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=back

=head1 METHODS

=over 4 

=item new HASHREF

Creates a new record.  To add the record to the database, see L<"insert">.

=cut

sub table { 'cust_credit_refund'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub insert {
  my $self = shift;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->check;
  return $error if $error;

  $error = $self->SUPER::insert;

  my $cust_refund =
    qsearchs('cust_refund', { 'refundnum' => $self->refundnum } )
  or do {
    $dbh->rollback if $oldAutoCommit;
    return "unknown cust_refund.refundnum: ". $self->refundnum
  };

  my $refund_total = 0;
  $refund_total += $_ foreach map { $_->amount }
    qsearch('cust_credit_refund', { 'refundnum' => $self->refundnum } );

  if ( $refund_total > $cust_refund->refund ) {
    $dbh->rollback if $oldAutoCommit;
    return "total cust_credit_refund.amount $refund_total for refundnum ".
           $self->refundnum.
           " greater than cust_refund.refund ". $cust_refund->refund;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';
}

=item delete

Currently unimplemented (accounting reasons).

=cut

sub delete {
  return "Can't (yet?) delete cust_credit_refund records!";
}

=item replace OLD_RECORD

Currently unimplemented (accounting reasons).

=cut

sub replace {
   return "Can't (yet?) modify cust_credit_refund records!";
}

=item check

Checks all fields to make sure this is a valid payment.  If there is an error,
returns the error, otherwise returns false.  Called by the insert method.

=cut

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('creditrefundnum')
    || $self->ut_number('crednum')
    || $self->ut_number('refundnum')
    || $self->ut_money('amount')
    || $self->ut_numbern('_date')
  ;
  return $error if $error;

  return "amount must be > 0" if $self->amount <= 0;

  $self->_date(time) unless $self->_date;

  return "unknown cust_credit.crednum: ". $self->crednum
    unless qsearchs( 'cust_credit', { 'crednum' => $self->crednum } );

  $self->SUPER::check;
}

=item cust_refund

Returns the refund (see L<FS::cust_refund>)

=cut

sub cust_refund {
  my $self = shift;
  qsearchs( 'cust_refund', { 'refundnum' => $self->refundnum } );
}

=item cust_credit

Returns the credit (see L<FS::cust_credit>)

=cut

sub cust_credit {
  my $self = shift;
  qsearchs( 'cust_credit', { 'crednum' => $self->crednum } );
}

=back

=head1 VERSION

$Id: cust_credit_refund.pm,v 1.9.8.1 2003-06-23 22:19:31 khoff Exp $

=head1 BUGS

Delete and replace methods.

the checks for over-applied refunds could be better done like the ones in
cust_bill_credit

=head1 SEE ALSO

L<FS::cust_credit>, L<FS::cust_refund>, L<FS::Record>, schema.html from the
base documentation.

=cut

1;

