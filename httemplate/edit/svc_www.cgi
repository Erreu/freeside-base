<!-- mason kludge -->
<%

my( $svcnum,  $pkgnum, $svcpart, $part_svc, $svc_www );
if ( $cgi->param('error') ) {
  $svc_www = new FS::svc_www ( {
    map { $_, scalar($cgi->param($_)) } fields('svc_www')
  } );
  $svcnum = $svc_www->svcnum;
  $pkgnum = $cgi->param('pkgnum');
  $svcpart = $cgi->param('svcpart');
  $part_svc=qsearchs('part_svc',{'svcpart'=>$svcpart});
  die "No part_svc entry!" unless $part_svc;
} else {
  my($query) = $cgi->keywords;
  if ( $query =~ /^(\d+)$/ ) { #editing
    $svcnum=$1;
    $svc_www=qsearchs('svc_www',{'svcnum'=>$svcnum})
      or die "Unknown (svc_www) svcnum!";

    my($cust_svc)=qsearchs('cust_svc',{'svcnum'=>$svcnum})
      or die "Unknown (cust_svc) svcnum!";

    $pkgnum=$cust_svc->pkgnum;
    $svcpart=$cust_svc->svcpart;
  
    $part_svc=qsearchs('part_svc',{'svcpart'=>$svcpart});
    die "No part_svc entry!" unless $part_svc;

  } else { #adding

    $svc_www = new FS::svc_www({});

    foreach $_ (split(/-/,$query)) { #get & untaint pkgnum & svcpart
      $pkgnum=$1 if /^pkgnum(\d+)$/;
      $svcpart=$1 if /^svcpart(\d+)$/;
    }
    $part_svc=qsearchs('part_svc',{'svcpart'=>$svcpart});
    die "No part_svc entry!" unless $part_svc;

    $svcnum='';

    #set fixed and default fields from part_svc
    foreach my $part_svc_column (
      grep { $_->columnflag } $part_svc->all_part_svc_column
    ) {
      $svc_www->setfield( $part_svc_column->columnname,
                          $part_svc_column->columnvalue,
                        );
    }

  }
}
my $action = $svc_www->svcnum ? 'Edit' : 'Add';

my( %svc_acct, %arec );
if ($pkgnum) {

  my($u_part_svc,@u_acct_svcparts);
  foreach $u_part_svc ( qsearch('part_svc',{'svcdb'=>'svc_acct'}) ) {
    push @u_acct_svcparts,$u_part_svc->getfield('svcpart');
  }

  my($cust_pkg)=qsearchs('cust_pkg',{'pkgnum'=>$pkgnum});
  my($custnum)=$cust_pkg->getfield('custnum');
  my($i_cust_pkg);
  foreach $i_cust_pkg ( qsearch('cust_pkg',{'custnum'=>$custnum}) ) {
    my($cust_pkgnum)=$i_cust_pkg->getfield('pkgnum');
    my($acct_svcpart);
    foreach $acct_svcpart (@u_acct_svcparts) {   #now find the corresponding 
                                              #record(s) in cust_svc ( for this
                                              #pkgnum ! )
      my($i_cust_svc);
      foreach $i_cust_svc ( qsearch('cust_svc',{'pkgnum'=>$cust_pkgnum,'svcpart'=>$acct_svcpart}) ) {
        my($svc_acct)=qsearchs('svc_acct',{'svcnum'=>$i_cust_svc->getfield('svcnum')});
        $svc_acct{$svc_acct->getfield('svcnum')}=
          $svc_acct->part_svc->svc. ': '. $svc_acct->email;
      }  
    }
  }


  my($d_part_svc,@d_acct_svcparts);
  foreach $d_part_svc ( qsearch('part_svc',{'svcdb'=>'svc_domain'}) ) {
    push @d_acct_svcparts,$d_part_svc->getfield('svcpart');
  }

  foreach $i_cust_pkg ( qsearch('cust_pkg',{'custnum'=>$custnum}) ) {
    my($cust_pkgnum)=$i_cust_pkg->getfield('pkgnum');
    my($acct_svcpart);
    foreach $acct_svcpart (@d_acct_svcparts) {
      my($i_cust_svc);
      foreach $i_cust_svc ( qsearch('cust_svc',{'pkgnum'=>$cust_pkgnum,'svcpart'=>$acct_svcpart}) ) {
        my($svc_domain)=qsearchs('svc_domain',{'svcnum'=>$i_cust_svc->getfield('svcnum')});
        my $domain_rec;
        foreach $domain_rec ( qsearch('domain_record',{
            'svcnum'  => $svc_domain->svcnum,
            'rectype' => 'A' } ),
        qsearch('domain_record',{
            'svcnum'  => $svc_domain->svcnum,
            'rectype' => 'CNAME'
            } ) ) {
          $arec{$domain_rec->recnum} =
            $domain_rec->reczone eq '@'
              ? $svc_domain->domain
              : $domain_rec->reczone. '.'. $svc_domain->domain;
        }
        $arec{'@.'. $svc_domain->domain} = $svc_domain->domain
          unless qsearchs('domain_record', { svcnum  => $svc_domain->svcnum,
                                             reczone => '@',                } );
        $arec{'www.'. $svc_domain->domain} = 'www.'. $svc_domain->domain
          unless qsearchs('domain_record', { svcnum  => $svc_domain->svcnum,
                                             reczone => 'www',              } );
      }
    }
  }

} elsif ( $action eq 'Edit' ) {

  my($domain_rec) = qsearchs('domain_record', { 'recnum'=>$svc_www->recnum });
  $arec{$svc_www->recnum} = join '.', $domain_rec->recdata, $domain_rec->reczone;

} else {
  die "\$action eq Add, but \$pkgnum is null!\n";
}


my $p1 = popurl(1);
print header("Web Hosting $action", '');

print qq!<FONT SIZE="+1" COLOR="#ff0000">Error: !, $cgi->param('error'),
      "</FONT>"
  if $cgi->param('error');

print qq!<FORM ACTION="${p1}process/svc_www.cgi" METHOD=POST>!;

#display

 

#svcnum
print qq!<INPUT TYPE="hidden" NAME="svcnum" VALUE="$svcnum">!;
print qq!Service #<B>!, $svcnum ? $svcnum : "(NEW)", "</B><BR><BR>";

#pkgnum
print qq!<INPUT TYPE="hidden" NAME="pkgnum" VALUE="$pkgnum">!;
 
#svcpart
print qq!<INPUT TYPE="hidden" NAME="svcpart" VALUE="$svcpart">!;

my($recnum,$usersvc)=(
  $svc_www->recnum,
  $svc_www->usersvc,
);

print &ntable("#cccccc",2),
      '<TR><TD ALIGN="right">Zone</TD><TD><SELECT NAME="recnum" SIZE=1>';
foreach $_ (keys %arec) {
  print "<OPTION", $_ eq $recnum ? " SELECTED" : "",
        qq! VALUE="$_">$arec{$_}!;
}
print "</SELECT></TD></TR>";

print '<TR><TD ALIGN="right">Username</TD><TD><SELECT NAME="usersvc" SIZE=1>';
foreach $_ (keys %svc_acct) {
  print "<OPTION", ($_ eq $usersvc) ? " SELECTED" : "",
        qq! VALUE="$_">$svc_acct{$_}!;
}
print "</SELECT></TD></TR>";

print '</TABLE><BR><INPUT TYPE="submit" VALUE="Submit">';

print <<END;

    </FORM>
  </BODY>
</HTML>
END
%>
