<%

my $conf = new FS::Conf;
die "Customer deletions not enabled" unless $conf->exists('deletecustomers');

$cgi->param('custnum') =~ /^(\d+)$/;
my $custnum = $1;
my $new_custnum;
if ( $cgi->param('new_custnum') ) {
  $cgi->param('new_custnum') =~ /^(\d+)$/
    or die "Illegal new customer number: ". $cgi->param('new_custnum');
  $new_custnum = $1;
} else {
  $new_custnum = '';
}
my $cust_main = qsearchs( 'cust_main', { 'custnum' => $custnum } )
  or die "Customer not found: $custnum";

my $error = $cust_main->delete($new_custnum);

if ( $error ) {
  $cgi->param('error', $error);
  print $cgi->redirect(popurl(2). "delete-customer.cgi?". $cgi->query_string );
} elsif ( $new_custnum ) {
  print $cgi->redirect(popurl(3). "view/cust_main.cgi?$new_custnum");
} else {
  print $cgi->redirect(popurl(3));
}
%>
