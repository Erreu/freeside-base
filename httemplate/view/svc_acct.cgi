<!-- mason kludge -->
<%

my $conf = new FS::Conf;

my($query) = $cgi->keywords;
$query =~ /^(\d+)$/;
my $svcnum = $1;
my $svc_acct = qsearchs('svc_acct',{'svcnum'=>$svcnum});
die "Unknown svcnum" unless $svc_acct;

#false laziness w/all svc_*.cgi
my $cust_svc = qsearchs( 'cust_svc' , { 'svcnum' => $svcnum } );
my $pkgnum = $cust_svc->getfield('pkgnum');
my($cust_pkg, $custnum);
if ($pkgnum) {
  $cust_pkg = qsearchs( 'cust_pkg', { 'pkgnum' => $pkgnum } );
  $custnum = $cust_pkg->custnum;
} else {
  $cust_pkg = '';
  $custnum = '';
}
#eofalse

my $part_svc = qsearchs('part_svc',{'svcpart'=> $cust_svc->svcpart } );
die "Unknown svcpart" unless $part_svc;

my $domain;
if ( $svc_acct->domsvc ) {
  my $svc_domain = qsearchs('svc_domain', { 'svcnum' => $svc_acct->domsvc } );
  die "Unknown domain" unless $svc_domain;
  $domain = $svc_domain->domain;
} else {
  die "No svc_domain.svcnum record for svc_acct.domsvc: ". $cust_svc->domsvc;
}

%>

<SCRIPT>
function areyousure(href) {
    if (confirm("Permanently delete this account?") == true)
        window.location.href = href;
}
</SCRIPT>

<%= header('Account View', menubar(
  ( ( $pkgnum || $custnum )
    ? ( "View this package (#$pkgnum)" => "${p}view/cust_pkg.cgi?$pkgnum",
        "View this customer (#$custnum)" => "${p}view/cust_main.cgi?$custnum",
      )
    : ( "Cancel this (unaudited) account" =>
          "javascript:areyousure(\'${p}misc/cancel-unaudited.cgi?$svcnum\')" )
  ),
  "Main menu" => $p,
)) %>

<%

#if ( $cust_pkg && $cust_pkg->part_pkg->plan eq 'sqlradacct_hour' ) {
if (    $part_svc->part_export('sqlradius')
     || $part_svc->part_export('sqlradius_withdomain')
) {

  my $last_bill;
  my %plandata;
  if ( $cust_pkg ) {
    #false laziness w/httemplate/edit/part_pkg... this stuff doesn't really
    #belong in plan data
    %plandata = map { /^(\w+)=(.*)$/; ( $1 => $2 ); }
                    split("\n", $cust_pkg->part_pkg->plandata );

    $last_bill = $cust_pkg->last_bill;
  } else {
    $last_bill = 0;
    %plandata = ();
  }

  my $seconds = $svc_acct->seconds_since_sqlradacct( $last_bill, time );
  my $hour = int($seconds/3600);
  my $min = int( ($seconds%3600) / 60 );
  my $sec = $seconds%60;

  my $input = $svc_acct->attribute_since_sqlradacct(
    $last_bill, time, 'AcctInputOctets'
  ) / 1048576;
  my $output = $svc_acct->attribute_since_sqlradacct(
    $last_bill, time, 'AcctOutputOctets'
  ) / 1048576;

  if ( $seconds ) {
    print "Online <B>$hour</B>h <B>$min</B>m <B>$sec</B>s";
  } else {
    print 'Has not logged on';
  }

  if ( $cust_pkg ) {
    print ' since last bill ('. time2str("%C", $last_bill). ') - '. 
          $plandata{recur_included_hours}. ' total hours in plan<BR>';
  } else {
    print ' (no billing cycle available for unaudited account)<BR>';
  }

  print 'Input: <B>'. sprintf("%.3f", $input). '</B> megabytes<BR>';
  print 'Output: <B>'. sprintf("%.3f", $output). '</B> megabytes<BR>';

  print '<BR>';

}

#print qq!<BR><A HREF="../misc/sendconfig.cgi?$svcnum">Send account information</A>!;

print qq!<A HREF="${p}edit/svc_acct.cgi?$svcnum">Edit this information</A><BR>!.
      &ntable("#cccccc"). '<TR><TD>'. &ntable("#cccccc",2).
      "<TR><TD ALIGN=\"right\">Service number</TD>".
        "<TD BGCOLOR=\"#ffffff\">$svcnum</TD></TR>".
      "<TR><TD ALIGN=\"right\">Service</TD>".
        "<TD BGCOLOR=\"#ffffff\">". $part_svc->svc. "</TD></TR>".
      "<TR><TD ALIGN=\"right\">Username</TD>".
        "<TD BGCOLOR=\"#ffffff\">". $svc_acct->username. "</TD></TR>"
;

print "<TR><TD ALIGN=\"right\">Domain</TD>".
        "<TD BGCOLOR=\"#ffffff\">". $domain, "</TD></TR>";

print "<TR><TD ALIGN=\"right\">Password</TD><TD BGCOLOR=\"#ffffff\">";
my $password = $svc_acct->_password;
if ( $password =~ /^\*\w+\* (.*)$/ ) {
  $password = $1;
  print "<I>(login disabled)</I> ";
}
if ( $conf->exists('showpasswords') ) {
  print '<PRE>'. encode_entities($password). '</PRE>';
} else {
  print "<I>(hidden)</I>";
}
print "</TR></TD>";
$password = '';

if ( $conf->exists('security_phrase') ) {
  my $sec_phrase = $svc_acct->sec_phrase;
  print '<TR><TD ALIGN="right">Security phrase</TD><TD BGCOLOR="#ffffff">'.
        $svc_acct->sec_phrase. '</TD></TR>';
}

my $svc_acct_pop = $svc_acct->popnum
                     ? qsearchs('svc_acct_pop',{'popnum'=>$svc_acct->popnum})
                     : '';
print "<TR><TD ALIGN=\"right\">Access number</TD>".
      "<TD BGCOLOR=\"#ffffff\">". $svc_acct_pop->text. '</TD></TR>'
  if $svc_acct_pop;

if ($svc_acct->uid ne '') {
  print "<TR><TD ALIGN=\"right\">Uid</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->uid. "</TD></TR>",
        "<TR><TD ALIGN=\"right\">Gid</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->gid. "</TD></TR>",
        "<TR><TD ALIGN=\"right\">GECOS</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->finger. "</TD></TR>",
        "<TR><TD ALIGN=\"right\">Home directory</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->dir. "</TD></TR>",
        "<TR><TD ALIGN=\"right\">Shell</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->shell. "</TD></TR>",
        "<TR><TD ALIGN=\"right\">Quota</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->quota. "</TD></TR>"
  ;
} else {
  print "<TR><TH COLSPAN=2>(No shell account)</TH></TR>";
}

if ($svc_acct->slipip) {
  print "<TR><TD ALIGN=\"right\">IP address</TD><TD BGCOLOR=\"#ffffff\">".
        ( ( $svc_acct->slipip eq "0.0.0.0" || $svc_acct->slipip eq '0e0' )
          ? "<I>(Dynamic)</I>"
          : $svc_acct->slipip
        ). "</TD>";
  my($attribute);
  foreach $attribute ( grep /^radius_/, $svc_acct->fields ) {
    #warn $attribute;
    $attribute =~ /^radius_(.*)$/;
    my $pattribute = $FS::raddb::attrib{$1};
    print "<TR><TD ALIGN=\"right\">Radius (reply) $pattribute</TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->getfield($attribute).
          "</TD></TR>";
  }
  foreach $attribute ( grep /^rc_/, $svc_acct->fields ) {
    #warn $attribute;
    $attribute =~ /^rc_(.*)$/;
    my $pattribute = $FS::raddb::attrib{$1};
    print "<TR><TD ALIGN=\"right\">Radius (check) $pattribute: </TD>".
          "<TD BGCOLOR=\"#ffffff\">". $svc_acct->getfield($attribute).
          "</TD></TR>";
  }
} else {
  print "<TR><TH COLSPAN=2>(No SLIP/PPP account)</TH></TR>";
}

print '<TR><TD ALIGN="right">RADIUS groups</TD><TD BGCOLOR="#ffffff">'.
      join('<BR>', $svc_acct->radius_groups). '</TD></TR>';

# Can this be abstracted further?  Maybe a library function like
# widget('HTML', 'view', $svc_acct) ?  It would definitely make UI 
# style management easier.

foreach (sort { $a cmp $b } $svc_acct->virtual_fields) {
  print $svc_acct->pvf($_)->widget('HTML', 'view', $svc_acct->getfield($_)),
      "\n";
}
%>
</TABLE></TD></TR></TABLE>
<%

print '<BR><BR>';

print join("\n", $conf->config('svc_acct-notes') ). '<BR><BR>'.
      joblisting({'svcnum'=>$svcnum}, 1). '</BODY></HTML>';

%>
