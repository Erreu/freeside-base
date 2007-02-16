package FS::payinfo_Mixin;

use strict;
use Business::CreditCard;
use FS::payby;

=head1 NAME

FS::payinfo_Mixin - Mixin class for records in tables that contain payinfo.  

=head1 SYNOPSIS

package FS::some_table;
use vars qw(@ISA);
@ISA = qw( FS::payinfo_Mixin FS::Record );

=head1 DESCRIPTION

This is a mixin class for records that contain payinfo. 

This class handles the following functions for payinfo...

Payment Mask (Generation and Storage)
Data Validation (parent checks need to be sure to call this)
Encryption - In the Future (Pull from Record.pm)
Bad Card Stuff - In the Future (Integrate Banned Pay)
Currency - In the Future

=head1 FIELDS

=over 4

=item payby

The following payment types (payby) are supported:

For Customers (cust_main):
'CARD' (credit card - automatic), 'DCRD' (credit card - on-demand),
'CHEK' (electronic check - automatic), 'DCHK' (electronic check - on-demand),
'LECB' (Phone bill billing), 'BILL' (billing), 'COMP' (free), or
'PREPAY' (special billing type: applies a credit and sets billing type to I<BILL> - see L<FS::prepay_credit>)

For Refunds (cust_refund):
'CARD' (credit cards), 'CHEK' (electronic check/ACH),
'LECB' (Phone bill billing), 'BILL' (billing), 'CASH' (cash),
'WEST' (Western Union), 'MCRD' (Manual credit card), 'CBAK' Chargeback, or 'COMP' (free)


For Payments (cust_pay):
'CARD' (credit cards), 'CHEK' (electronic check/ACH),
'LECB' (phone bill billing), 'BILL' (billing), 'PREP' (prepaid card),
'CASH' (cash), 'WEST' (Western Union), or 'MCRD' (Manual credit card)
'COMP' (free) is depricated as a payment type in cust_pay

=cut 

# was this supposed to do something?
 
#sub payby {
#  my($self,$payby) = @_;
#  if ( defined($payby) ) {
#    $self->setfield('payby', $payby);
#  } 
#  return $self->getfield('payby')
#}

=item payinfo

Payment information (payinfo) can be one of the following types:

Card Number, P.O., comp issuer (4-8 lowercase alphanumerics; think username) or prepayment identifier (see L<FS::prepay_credit>)

=cut

sub payinfo {
  my($self,$payinfo) = @_;
  if ( defined($payinfo) ) {
    $self->setfield('payinfo', $payinfo); # This is okay since we are the 'setter'
    $self->paymask($self->mask_payinfo());
  } else {
    $payinfo = $self->getfield('payinfo'); # This is okay since we are the 'getter'
    return $payinfo;
  }
}

=item paycvv

Card Verification Value, "CVV2" (also known as CVC2 or CID), the 3 or 4 digit number on the back (or front, for American Express) of the credit card

=cut

sub paycvv {
  my($self,$paycvv) = @_;
  # This is only allowed in cust_main... Even then it really shouldn't be stored...
  if ($self->table eq 'cust_main') {
    if ( defined($paycvv) ) {
      $self->setfield('paycvv', $paycvv); # This is okay since we are the 'setter'
    } else {
      $paycvv = $self->getfield('paycvv'); # This is okay since we are the 'getter'
      return $paycvv;
    }
  } else {
#    warn "This doesn't work for other tables besides cust_main
    '';
  } 
}

=item paymask

=cut

sub paymask {
  my($self, $paymask) = @_;

  if ( defined($paymask) && $paymask ne '' ) {
    # I hate this little bit of magic...  I don't expect it to cause a problem,
    # but who knows...  If the payinfo is passed in masked then ignore it and
    # set it based on the payinfo.  The only guy that should call this in this
    # way is... $self->payinfo
    $self->setfield('paymask', $self->mask_payinfo());

  } else {

    $paymask=$self->getfield('paymask');
    if (!defined($paymask) || $paymask eq '') {
      # Generate it if it's blank - Note that we're not going to set it - just
      # generate
      $paymask = $self->mask_payinfo();
    }

  }

  return $paymask;
}

=back

=head1 METHODS

=over 4

=item mask_payinfo [ PAYBY, PAYINFO ]

This method converts the payment info (credit card, bank account, etc.) into a
masked string.

Optionally, an arbitrary payby and payinfo can be passed.

=cut

sub mask_payinfo {
  my $self = shift;
  my $payby   = scalar(@_) ? shift : $self->payby;
  my $payinfo = scalar(@_) ? shift : $self->payinfo;

  # Check to see if it's encrypted...
  my $paymask;
  if ( $self->is_encrypted($payinfo) ) {
    $paymask = 'N/A';
  } else {
    # if not, mask it...
    if ($payby eq 'CARD' || $payby eq 'DCRD' || $payby eq 'MCRD') {
      # Credit Cards (Show first and last four)
      $paymask = substr($payinfo,0,6).
                 'x'x(length($payinfo)-10).
                 substr($payinfo,(length($payinfo)-4));
    } elsif ($payby eq 'CHEK' || $payby eq 'DCHK' ) {
      # Checks (Show last 2 @ bank)
      my( $account, $aba ) = split('@', $payinfo );
      $paymask = 'x'x(length($account)-2).
                 substr($account,(length($account)-2))."@".$aba;
    } else { # Tie up loose ends
      $paymask = $payinfo;
    }
  }
  return $paymask;
}

=cut

sub _mask_payinfo {
  my $self = shift;

=item payinfo_check

Checks payby and payinfo.

For Customers (cust_main):
'CARD' (credit card - automatic), 'DCRD' (credit card - on-demand),
'CHEK' (electronic check - automatic), 'DCHK' (electronic check - on-demand),
'LECB' (Phone bill billing), 'BILL' (billing), 'COMP' (free), or
'PREPAY' (special billing type: applies a credit - see L<FS::prepay_credit> and sets billing type to I<BILL>)

For Refunds (cust_refund):
'CARD' (credit cards), 'CHEK' (electronic check/ACH),
'LECB' (Phone bill billing), 'BILL' (billing), 'CASH' (cash),
'WEST' (Western Union), 'MCRD' (Manual credit card), 'CBAK' (Chargeback),  or 'COMP' (free)

For Payments (cust_pay):
'CARD' (credit cards), 'CHEK' (electronic check/ACH),
'LECB' (phone bill billing), 'BILL' (billing), 'PREP' (prepaid card),
'CASH' (cash), 'WEST' (Western Union), or 'MCRD' (Manual credit card)
'COMP' (free) is depricated as a payment type in cust_pay

=cut

sub payinfo_check {
  my $self = shift;

  FS::payby->can_payby($self->table, $self->payby)
    or return "Illegal payby: ". $self->payby;

  if ( $self->payby eq 'CARD' ) {
    my $payinfo = $self->payinfo;
    $payinfo =~ s/\D//g;
    $self->payinfo($payinfo);
    if ( $self->payinfo ) {
      $self->payinfo =~ /^(\d{13,16})$/
        or return "Illegal (mistyped?) credit card number (payinfo)";
      $self->payinfo($1);
      validate($self->payinfo) or return "Illegal credit card number";
      return "Unknown card type" if cardtype($self->payinfo) eq "Unknown";
    } else {
      $self->payinfo('N/A');
    }
  } else {
    my $error = $self->ut_textn('payinfo');
    return $error if $error;
  }
}

=head1 BUGS

Have to add the future items...

=head1 SEE ALSO

L<FS::payby>, L<FS::Record>

=cut

1;

