#!/usr/bin/perl -Tw
#
# $Id: cust_main.cgi,v 1.19 2001-04-22 01:38:39 ivan Exp $
#
# Usage: cust_main.cgi custnum
#        http://server.name/path/cust_main.cgi?custnum
#
# the payment history section could use some work, see below
# 
# ivan@voicenet.com 96-nov-29 -> 96-dec-11
#
# added navigation bar (go to main menu ;)
# ivan@voicenet.com 97-jan-30
#
# changes to the way credits/payments are applied (the links are here).
# ivan@voicenet.com 97-apr-21
#
# added debugging code to diagnose CPU sucking problem.
# ivan@voicenet.com 97-may-19
#
# CPU sucking problem was in comment code?  fixed?
# ivan@voicenet.com 97-may-22
#
# rewrote for new API
# ivan@voicenet.com 97-jul-22
#
# Changes to allow page to work at a relative position in server
# Changed 'day' to 'daytime' because Pg6.3 reserves the day word
#       bmccane@maxbaud.net     98-apr-3
#
# lose background, FS::CGI ivan@sisd.com 98-sep-2
#
# $Log: cust_main.cgi,v $
# Revision 1.19  2001-04-22 01:38:39  ivan
# svc_domain needs to import dbh sub from Record
# view/cust_main.cgi needs to use ->owed method, not check (depriciated) owed field
# search/cust_bill.cgi redirect error when there's only one invoice
#
# Revision 1.18  1999/08/12 04:16:01  ivan
# hidecancelledpackages config option
#
# Revision 1.17  1999/04/15 16:44:36  ivan
# delete customers
#
# Revision 1.16  1999/04/09 04:22:34  ivan
# also table()
#
# Revision 1.15  1999/04/09 03:52:55  ivan
# explicit & for table/itable/ntable
#
# Revision 1.14  1999/04/08 04:04:37  ivan
# eliminate double // in links
#
# Revision 1.13  1999/02/28 00:04:00  ivan
# removed misleading comments
#
# Revision 1.12  1999/02/07 09:59:40  ivan
# more mod_perl fixes, and bugfixes Peter Wemm sent via email
#
# Revision 1.11  1999/01/25 12:26:04  ivan
# yet more mod_perl stuff
#
# Revision 1.10  1999/01/19 05:14:19  ivan
# for mod_perl: no more top-level my() variables; use vars instead
# also the last s/create/new/;
#
# Revision 1.9  1999/01/18 09:41:43  ivan
# all $cgi->header calls now include ( '-expires' => 'now' ) for mod_perl
# (good idea anyway)
#
# Revision 1.8  1999/01/18 09:22:35  ivan
# changes to track email addresses for email invoicing
#
# Revision 1.7  1998/12/30 23:03:34  ivan
# bugfixes; fields isn't exported by derived classes
#
# Revision 1.6  1998/12/23 02:42:33  ivan
# remove double '/' in link urls
#
# Revision 1.5  1998/12/23 02:36:28  ivan
# use FS::cust_refund; to eliminate warning
#
# Revision 1.4  1998/12/17 09:57:21  ivan
# s/CGI::(Base|Request)/CGI.pm/;
#
# Revision 1.3  1998/11/15 13:14:20  ivan
# first pass as per-customer custom pricing
#
# Revision 1.2  1998/11/13 11:28:08  ivan
# s/CGI-modules/CGI.pm/;, relative URL's with popurl
#

use strict;
use vars qw ( $cgi $query $custnum $cust_main $hashref $agent $referral 
              @packages $package @history @bills $bill @credits $credit
              $balance $item @agents @referrals @invoicing_list $n1 $conf ); 
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Date::Format;
use FS::UID qw(cgisuidsetup);
use FS::Record qw(qsearchs qsearch);
use FS::CGI qw(header menubar popurl table itable ntable);
use FS::cust_credit;
use FS::cust_pay;
use FS::cust_bill;
use FS::part_pkg;
use FS::cust_pkg;
use FS::part_referral;
use FS::agent;
use FS::cust_main;
use FS::cust_refund;

$cgi = new CGI;
&cgisuidsetup($cgi);

$conf = new FS::Conf;

print $cgi->header( '-expires' => 'now' ), header("Customer View", menubar(
  'Main Menu' => popurl(2)
));

die "No customer specified (bad URL)!" unless $cgi->keywords;
($query) = $cgi->keywords; # needs parens with my, ->keywords returns array
$query =~ /^(\d+)$/;
$custnum = $1;
$cust_main = qsearchs('cust_main',{'custnum'=>$custnum});
die "Customer not found!" unless $cust_main;
$hashref = $cust_main->hashref;

print &itable(), '<TR><TD><A NAME="cust_main"></A>';

print qq!<A HREF="!, popurl(2), 
      qq!edit/cust_main.cgi?$custnum">Edit this customer</A>!;
print qq! | <A HREF="!, popurl(2), 
      qq!misc/delete-customer.cgi?$custnum"> Delete this customer</A>!
  if $conf->exists('deletecustomers');
print &ntable("#c0c0c0"), "<TR><TD>", &ntable("#c0c0c0",2),
      '<TR><TD ALIGN="right">Customer number</TD><TD BGCOLOR="#ffffff">',
      $custnum, '</TD></TR>',
;

@agents = qsearch( 'agent', {} );
unless ( scalar(@agents) == 1 ) {
  $agent = qsearchs('agent',{
    'agentnum' => $cust_main->agentnum
  } );
  print '<TR><TD ALIGN="right">Agent</TD><TD BGCOLOR="#ffffff">',
        $agent->agentnum, ": ", $agent->agent, '</TD></TR>';
}
@referrals = qsearch( 'part_referral', {} );
unless ( scalar(@referrals) == 1 ) {
  my $referral = qsearchs('part_referral', {
    'refnum' => $cust_main->refnum
  } );
  print '<TR><TD ALIGN="right">Referral</TD><TD BGCOLOR="#ffffff">',
        $referral->refnum, ": ", $referral->referral, '</TD></TR>';
}
print '<TR><TD ALIGN="right">Order taker</TD><TD BGCOLOR="#ffffff">',
  $cust_main->otaker, '</TD></TR>';

print '</TABLE></TD></TR></TABLE>';

print '</TD><TD ROWSPAN=2>';

print "Contact information", &ntable("#c0c0c0"), "<TR><TD>",
      &ntable("#c0c0c0",2),
  '<TR><TD ALIGN="right">Contact name<BR>(last, first)</TD>',
    '<TD COLSPAN=3 BGCOLOR="#ffffff">',
    $cust_main->last, ', ', $cust_main->first,
    '</TD><TD ALIGN="right">SS#</TD><TD BGCOLOR="#ffffff">',
    $cust_main->ss || '&nbsp', '</TD></TR>',
  '<TR><TD ALIGN="right">Company</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
    $cust_main->company,
    '</TD></TR>',
  '<TR><TD ALIGN="right">Address</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
    $cust_main->address1,
    '</TD></TR>',
;
print '<TR><TD ALIGN="right">&nbsp;</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
      $cust_main->address2, '</TD></TR>'
  if $cust_main->address2;
print '<TR><TD ALIGN="right">City</TD><TD BGCOLOR="#ffffff">',
        $cust_main->city,
        '</TD><TD ALIGN="right">State</TD><TD BGCOLOR="#ffffff">',
        $cust_main->state,
        '</TD><TD ALIGN="right">Zip</TD><TD BGCOLOR="#ffffff">',
        $cust_main->zip, '</TD></TR>',
      '<TR><TD ALIGN="right">Country</TD><TD BGCOLOR="#ffffff">',
        $cust_main->country,
        '</TD></TR>',
;
print '<TR><TD ALIGN="right">Day Phone</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
        $cust_main->daytime || '&nbsp', '</TD></TR>',
      '<TR><TD ALIGN="right">Night Phone</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
        $cust_main->night || '&nbsp', '</TD></TR>',
      '<TR><TD ALIGN="right">Fax</TD><TD COLSPAN=5 BGCOLOR="#ffffff">',
        $cust_main->fax || '&nbsp', '</TD></TR>',
      '</TABLE>', "</TD></TR></TABLE>"
;

print '</TD></TR><TR><TD>';

@invoicing_list = $cust_main->invoicing_list;
print "Billing information (",
      qq!<A HREF="!, popurl(2), qq!/misc/bill.cgi?$custnum">!, "Bill now</A>)",
      &ntable("#c0c0c0"), "<TR><TD>", &ntable("#c0c0c0",2),
      '<TR><TD ALIGN="right">Tax exempt</TD><TD BGCOLOR="#ffffff">',
      $cust_main->tax ? 'yes' : 'no',
      '</TD></TR>',
      '<TR><TD ALIGN="right">Postal invoices</TD><TD BGCOLOR="#ffffff">',
      ( grep { $_ eq 'POST' } @invoicing_list ) ? 'yes' : 'no',
      '</TD></TR>',
      '<TR><TD ALIGN="right">Email invoices</TD><TD BGCOLOR="#ffffff">',
      join(', ', grep { $_ ne 'POST' } @invoicing_list ) || 'no',
      '</TD></TR>',
      '<TR><TD ALIGN="right">Billing type</TD><TD BGCOLOR="#ffffff">',
;

if ( $cust_main->payby eq 'CARD' ) {
  print 'Credit card</TD></TR>',
        '<TR><TD ALIGN="right">Card number</TD><TD BGCOLOR="#ffffff">',
        $cust_main->payinfo, '</TD></TR>',
        '<TR><TD ALIGN="right">Expiration</TD><TD BGCOLOR="#ffffff">',
        $cust_main->paydate, '</TD></TR>',
        '<TR><TD ALIGN="right">Name on card</TD><TD BGCOLOR="#ffffff">',
        $cust_main->payname, '</TD></TR>'
  ;
} elsif ( $cust_main->payby eq 'BILL' ) {
  print 'Billing</TD></TR>';
  print '<TR><TD ALIGN="right">P.O. </TD><TD BGCOLOR="#ffffff">',
        $cust_main->payinfo, '</TD></TR>',
    if $cust_main->payinfo;
  print '<TR><TD ALIGN="right">Expiration</TD><TD BGCOLOR="#ffffff">',
        $cust_main->paydate, '</TD></TR>',
        '<TR><TD ALIGN="right">Attention</TD><TD BGCOLOR="#ffffff">',
        $cust_main->payname, '</TD></TR>',
  ;
} elsif ( $cust_main->payby eq 'COMP' ) {
  print 'Complimentary</TD></TR>',
        '<TR><TD ALIGN="right">Authorized by</TD><TD BGCOLOR="#ffffff">',
        $cust_main->payinfo, '</TD></TR>',
        '<TR><TD ALIGN="right">Expiration</TD><TD BGCOLOR="#ffffff">',
        $cust_main->paydate, '</TD></TR>',
  ;
}

print "</TABLE></TD></TR></TABLE></TD></TR></TABLE>";

print qq!<BR><BR><A NAME="cust_pkg">Packages</A> !,
#      qq!<BR>Click on package number to view/edit package.!,
      qq!( <A HREF="!, popurl(2), qq!edit/cust_pkg.cgi?$custnum">Order and cancel packages</A> )!,
;

#display packages

#formatting
print qq!!, &table(), "\n",
      qq!<TR><TH COLSPAN=2 ROWSPAN=2>Package</TH><TH COLSPAN=5>!,
      qq!Dates</TH><TH COLSPAN=2 ROWSPAN=2>Services</TH></TR>\n!,
      qq!<TR><TH><FONT SIZE=-1>Setup</FONT></TH><TH>!,
      qq!<FONT SIZE=-1>Next bill</FONT>!,
      qq!</TH><TH><FONT SIZE=-1>Susp.</FONT></TH><TH><FONT SIZE=-1>Expire!,
      qq!</FONT></TH>!,
      qq!<TH><FONT SIZE=-1>Cancel</FONT></TH>!,
      qq!</TR>\n!;

#get package info
if ( $conf->exists('hidecancelledpackages') ) {
  @packages = $cust_main->ncancelled_pkgs;
} else {
  @packages = $cust_main->all_pkgs;
}

$n1 = '<TR>';
foreach $package (@packages) {
  my $pkgnum = $package->pkgnum;
  my $pkg = $package->part_pkg->pkg;
  my $comment = $package->part_pkg->comment;
  my $pkgview = popurl(2). "view/cust_pkg.cgi?$pkgnum";
  my @cust_svc = qsearch( 'cust_svc', { 'pkgnum' => $pkgnum } );
  my $rowspan = scalar(@cust_svc) || 1;

  my $button_cgi = new CGI;
  $button_cgi->param('clone', $package->part_pkg->pkgpart);
  $button_cgi->param('pkgnum', $package->pkgnum);
  my $button_url = popurl(2). "edit/part_pkg.cgi?". $button_cgi->query_string;

  #print $n1, qq!<TD ROWSPAN=$rowspan><A HREF="$pkgview">$pkgnum</A></TD>!,
  print $n1, qq!<TD ROWSPAN=$rowspan>$pkgnum</TD>!,
        qq!<TD ROWSPAN=$rowspan><FONT SIZE=-1>!,
        #qq!<A HREF="$pkgview">$pkg - $comment</A>!,
        qq!$pkg - $comment!,
        qq! ( <A HREF="$pkgview">Edit</A> | <A HREF="$button_url">Customize pricing</A> )</FONT></TD>!,
  ;
  for ( qw( setup bill susp expire cancel ) ) {
    print "<TD ROWSPAN=$rowspan><FONT SIZE=-1>", ( $package->getfield($_)
            ? time2str("%D", $package->getfield($_) )
            :  '&nbsp'
          ), '</FONT></TD>',
    ;
  }

  my $n2 = '';
  foreach my $cust_svc ( @cust_svc ) {
     my($label, $value, $svcdb) = $cust_svc->label;
     my($svcnum) = $cust_svc->svcnum;
     my($sview) = popurl(2). "view";
     print $n2,qq!<TD><A HREF="$sview/$svcdb.cgi?$svcnum"><FONT SIZE=-1>$label</FONT></A></TD>!,
           qq!<TD><A HREF="$sview/$svcdb.cgi?$svcnum"><FONT SIZE=-1>$value</FONT></A></TD>!;
     $n2="</TR><TR>";
  }
  $n1="</TR><TR>";
}  
print "</TR>";

#formatting
print "</TABLE>";

#formatting
print qq!<BR><BR><A NAME="history">Payment History!,
      qq!</A>!,
      qq! ( Click on invoice to view invoice/enter payment. | !,
      qq!<A HREF="!, popurl(2), qq!edit/cust_credit.cgi?$custnum">!,
      qq!Post credit / refund</A> )!;

#get payment history
#
# major problem: this whole thing is way too sloppy.
# minor problem: the description lines need better formatting.

@history = (); #needed for mod_perl :)

@bills = qsearch('cust_bill',{'custnum'=>$custnum});
foreach $bill (@bills) {
  my($bref)=$bill->hashref;
  push @history,
    $bref->{_date} . qq!\t<A HREF="!. popurl(2). qq!view/cust_bill.cgi?! .
    $bref->{invnum} . qq!">Invoice #! . $bref->{invnum} .
    qq! (Balance \$! . $bill->owed . qq!)</A>\t! .
    $bref->{charged} . qq!\t\t\t!;

  my(@payments)=qsearch('cust_pay',{'invnum'=> $bref->{invnum} } );
  my($payment);
  foreach $payment (@payments) {
    my($date,$invnum,$payby,$payinfo,$paid)=($payment->getfield('_date'),
                                             $payment->getfield('invnum'),
                                             $payment->getfield('payby'),
                                             $payment->getfield('payinfo'),
                                             $payment->getfield('paid'),
                      );
    push @history,
      "$date\tPayment, Invoice #$invnum ($payby $payinfo)\t\t$paid\t\t";
  }
}

@credits = qsearch('cust_credit',{'custnum'=>$custnum});
foreach $credit (@credits) {
  my($cref)=$credit->hashref;
  push @history,
    $cref->{_date} . "\tCredit #" . $cref->{crednum} . ", (Balance \$" .
    $cref->{credited} . ") by " . $cref->{otaker} . " - " .
    $cref->{reason} . "\t\t\t" . $cref->{amount} . "\t";

  my(@refunds)=qsearch('cust_refund',{'crednum'=> $cref->{crednum} } );
  my($refund);
  foreach $refund (@refunds) {
    my($rref)=$refund->hashref;
    push @history,
      $rref->{_date} . "\tRefund, Credit #" . $rref->{crednum} . " (" .
      $rref->{payby} . " " . $rref->{payinfo} . ") by " .
      $rref->{otaker} . " - ". $rref->{reason} . "\t\t\t\t" .
      $rref->{refund};
  }
}

        #formatting
        print &table(), <<END;
<TR>
  <TH>Date</TH>
  <TH>Description</TH>
  <TH><FONT SIZE=-1>Charge</FONT></TH>
  <TH><FONT SIZE=-1>Payment</FONT></TH>
  <TH><FONT SIZE=-1>In-house<BR>Credit</FONT></TH>
  <TH><FONT SIZE=-1>Refund</FONT></TH>
  <TH><FONT SIZE=-1>Balance</FONT></TH>
</TR>
END

#display payment history

$balance = 0;
foreach $item (sort keyfield_numerically @history) {
  my($date,$desc,$charge,$payment,$credit,$refund)=split(/\t/,$item);
  $charge ||= 0;
  $payment ||= 0;
  $credit ||= 0;
  $refund ||= 0;
  $balance += $charge - $payment;
  $balance -= $credit - $refund;

  print "<TR><TD><FONT SIZE=-1>",time2str("%D",$date),"</FONT></TD>",
	"<TD><FONT SIZE=-1>$desc</FONT></TD>",
	"<TD><FONT SIZE=-1>",
        ( $charge ? "\$".sprintf("%.2f",$charge) : '' ),
        "</FONT></TD>",
	"<TD><FONT SIZE=-1>",
        ( $payment ? "- \$".sprintf("%.2f",$payment) : '' ),
        "</FONT></TD>",
	"<TD><FONT SIZE=-1>",
        ( $credit ? "- \$".sprintf("%.2f",$credit) : '' ),
        "</FONT></TD>",
	"<TD><FONT SIZE=-1>",
        ( $refund ? "\$".sprintf("%.2f",$refund) : '' ),
        "</FONT></TD>",
	"<TD><FONT SIZE=-1>\$" . sprintf("%.2f",$balance),
        "</FONT></TD>",
        "\n";
}

#formatting
print "</TABLE>";

#end

#formatting
print <<END;

  </BODY>
</HTML>
END

#subroutiens
sub keyfield_numerically { (split(/\t/,$a))[0] <=> (split(/\t/,$b))[0] ; }

