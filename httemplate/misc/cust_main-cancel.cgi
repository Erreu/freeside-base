<%

#untaint custnum
my($query) = $cgi->keywords;
$query =~ /^(\d+)$/ || die "Illegal custnum";
my $custnum = $1;

my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } );

my @errors = $cust_main->cancel;
eidiot(join(' / ', @errors)) if scalar(@errors);

#print $cgi->redirect($p. "view/cust_main.cgi?". $cust_main->custnum);
print $cgi->redirect($p);

%>
