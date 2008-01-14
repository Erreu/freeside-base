%if ($error) {
%  errorpage($error);
%} else {
<% $cgi->redirect(popurl(3). "view/cust_main.cgi?$custnum#cust_pkg". $cust_pkg[0]->pkgnum ) %>
%}
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Order customer package');

#untaint custnum
$cgi->param('custnum') =~ /^(\d+)$/
  or die 'illegal custnum '. $cgi->param('custnum');
my $custnum = $1;
$cgi->param('pkgpart') =~ /^(\d+)$/
  or die 'illegal pkgpart '. $cgi->param('pkgpart');
my $pkgpart = $1;

my @cust_pkg = ();
my $error = FS::cust_pkg::order($custnum, [ $pkgpart ], [], \@cust_pkg, );

</%init>
