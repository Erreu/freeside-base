<!-- mason kludge -->
<%

#my $user = getotaker;
my $user = $FS::UID::user; #dumb 1.4 8-char workaround

print header('Current Receivables Report Results');

open (REPORT, "freeside-receivables-report -v $user |");

print '<PRE>';
while(<REPORT>) {
  print $_;
}
print '</PRE>';

print '</BODY></HTML>';

%>

