<!-- mason kludge -->
<%

#my $user = getotaker;
my $user = $FS::UID::user; #dumb 1.4 8-char workaround

$cgi->param('beginning') =~ /^([ 0-9\-\/]{0,10})$/;
my $beginning = $1;

$cgi->param('ending') =~ /^([ 0-9\-\/]{0,10})$/;
my $ending = $1;

print header('In House Credit Report Results');

open (REPORT, "freeside-credit-report -v -s $beginning -f $ending $user |");

print '<PRE>';
while(<REPORT>) {
  print $_;
}
print '</PRE>';

print '</BODY></HTML>';

%>

