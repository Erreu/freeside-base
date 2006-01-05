<!-- mason kludge -->
<%

my $rate;
if ( $cgi->param('error') ) {
  $rate = new FS::rate ( {
    map { $_, scalar($cgi->param($_)) } fields('rate')
  } );
} elsif ( $cgi->keywords ) {
  my($query) = $cgi->keywords;
  $query =~ /^(\d+)$/;
  $rate = qsearchs( 'rate', { 'ratenum' => $1 } );
} else { #adding
  $rate = new FS::rate {};
}
my $action = $rate->ratenum ? 'Edit' : 'Add';

my $p1 = popurl(1);

my %granularity = (
  '6'  => '6 second',
  '60' => 'minute',
);

my $nous = <<END;
  WHERE 0 < ( SELECT COUNT(*) FROM rate_prefix
               WHERE rate_region.regionnum = rate_prefix.regionnum
                 AND countrycode != '1'
            )
END

%>

<%= header("$action Rate plan", menubar(
      'Main Menu' => $p,
      'View all rate plans' => "${p}browse/rate.cgi",
    ))
%>

<% if ( $cgi->param('error') ) { %>
<FONT SIZE="+1" COLOR="#ff0000">Error: <%= $cgi->param('error') %></FONT><BR>
<% } %>

<FORM ACTION="<%=$p1%>process/rate.cgi" METHOD=POST>

<INPUT TYPE="hidden" NAME="ratenum" VALUE="<%= $rate->ratenum %>">

Rate plan
<INPUT TYPE="text" NAME="ratename" SIZE=32 VALUE="<%= $rate->ratename %>">
<BR><BR>

<%= table() %>
<TR>
  <TH>Region</TH>
  <TH>Prefix(es)</TH>
  <TH><FONT SIZE=-1>Included<BR>minutes</FONT></TH>
  <TH><FONT SIZE=-1>Charge per<BR>minute</FONT></TH>
  <TH><FONT SIZE=-1>Granularity</FONT></TH>
</TR>

<% foreach my $rate_region (
     qsearch( 'rate_region',
              {},
              '',
              "$nous ORDER BY regionname",
            )
   ) {
     my $n = $rate_region->regionnum;
     my $rate_detail =
       $rate->dest_detail($rate_region)
       || new FS::rate_region { 'min_included'    => 0,
                                'min_charge'      => 0,
                                'sec_granularity' => '60'
                              };
%>
  <TR>
    <TD><A HREF="<%=$p%>edit/rate_region.cgi?<%= $rate_region->regionnum %>"><%= $rate_region->regionname %></A></TD>
    <TD><%= $rate_region->prefixes_short %></TD>
    <TD><INPUT TYPE="text" SIZE=5 NAME="min_included<%=$n%>" VALUE="<%= $cgi->param("min_included$n") || $rate_detail->min_included %>"></TD>
    <TD>$<INPUT TYPE="text" SIZE=4 NAME="min_charge<%=$n%>" VALUE="<%= sprintf('%.2f', $cgi->param("min_charge$n") || $rate_detail->min_charge ) %>"></TD>
    <TD>
      <SELECT NAME="sec_granularity<%=$n%>">
        <% foreach my $granularity ( keys %granularity ) { %>
          <OPTION VALUE="<%=$granularity%>"<%= $granularity == ( $cgi->param("sec_granularity$n") || $rate_detail->sec_granularity ) ? ' SELECTED' : '' %>><%=$granularity{$granularity}%>
        <% } %>
      </SELECT>
  </TR>
<% } %>

<TR>
  <TD COLSPAN=5 ALIGN="center">
    <A HREF="<%=$p%>edit/rate_region.cgi"><I>Add a region</I></A>
  </TD>
</TR>

</TABLE>

<BR><INPUT TYPE="submit" VALUE="<%= 
  $rate->ratenum ? "Apply changes" : "Add rate plan"
%>">

    </FORM>
  </BODY>
</HTML>

