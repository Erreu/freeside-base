<%
  if ( driver_name =~ /^Pg$/ ) {
    my $dbname = (split(':', datasrc))[2];
    if ( $dbname =~ /[;=]/ ) {
      my %elements = map { /^(\w+)=(.*)$/; $1=>$2 } split(';', $dbname);
      $dbname = $elements{'dbname'};
    }
    open(DUMP,"pg_dump $dbname |");
  } else {
    eidiot "don't (yet) know how to dump ". driver_name. " databases\n";
  }

  http_header('Content-Type' => 'text/plain' );

  while (<DUMP>) {
    chomp;
%><%= $_ %><% }
   close DUMP;
%>
