<%

$cgi->param('pkgnum') =~ /^(\d+)$/;
my $pkgnum = $1;
$cgi->param('svcpart') =~ /^(\d+)$/;
my $svcpart = $1;
$cgi->param('svcnum') =~ /^(\d*)$/;
my $svcnum = $1;

unless ( $svcnum ) {
  my $part_svc = qsearchs('part_svc',{'svcpart'=>$svcpart});
  my $svcdb = $part_svc->getfield('svcdb');
  $cgi->param('link_field') =~ /^(\w+)$/;
  my $link_field = $1;
  my %search = ( $link_field => $cgi->param('link_value') );
  if ( $cgi->param('link_field2') =~ /^(\w+)$/ ) {
    $search{$1} = $cgi->param('link_value2');
  }
  my $svc_x = ( grep { $_->cust_svc->svcpart == $svcpart } 
                  qsearch( $svcdb, \%search )
              )[0];
  eidiot("$link_field not found!") unless $svc_x;
  $svcnum = $svc_x->svcnum;
}

my $old = qsearchs('cust_svc',{'svcnum'=>$svcnum});
die "svcnum not found!" unless $old;
my $conf = new FS::Conf;
my($error, $new);
if ( $old->pkgnum && ! $conf->exists('legacy_link-steal') ) {
  $error = "svcnum $svcnum already linked to package ". $old->pkgnum;
} else {
  $new = new FS::cust_svc ({
    'svcnum' => $svcnum,
    'pkgnum' => $pkgnum,
    'svcpart' => $svcpart,
  });

  $error = $new->replace($old);
}

unless ($error) {
  #no errors, so let's view this customer.
  my $custnum = $new->cust_pkg->custnum;
  print $cgi->redirect(popurl(3). "view/cust_main.cgi?$custnum".
                       "#cust_pkg$pkgnum" );
} else {
%>
<!-- mason kludge -->
<%
  idiot($error);
}

%>
