<!-- mason kludge -->
<%

my($query) = $cgi->keywords;
$query =~ /^(\d+)$/;
my $svcnum = $1;
my $svc_domain = qsearchs('svc_domain',{'svcnum'=>$svcnum});
die "Unknown svcnum" unless $svc_domain;

my $cust_svc = qsearchs('cust_svc',{'svcnum'=>$svcnum});
my $pkgnum = $cust_svc->getfield('pkgnum');
my($cust_pkg, $custnum);
if ($pkgnum) {
  $cust_pkg=qsearchs('cust_pkg',{'pkgnum'=>$pkgnum});
  $custnum=$cust_pkg->getfield('custnum');
} else {
  $cust_pkg = '';
  $custnum = '';
}

my $part_svc = qsearchs('part_svc',{'svcpart'=> $cust_svc->svcpart } );
die "Unknown svcpart" unless $part_svc;

my $email = '';
if ($svc_domain->catchall) {
  my $svc_acct = qsearchs('svc_acct',{'svcnum'=> $svc_domain->catchall } );
  die "Unknown svcpart" unless $svc_acct;
  $email = $svc_acct->email;
}

my $domain = $svc_domain->domain;

%>

<%= header('Domain View', menubar(
  ( ( $pkgnum || $custnum )
    ? ( "View this customer (#$custnum)" => "${p}view/cust_main.cgi?$custnum",
      )
    : ( "Cancel this (unaudited) domain" =>
          "${p}misc/cancel-unaudited.cgi?$svcnum" )
  ),
  "Main menu" => $p,
)) %>

Service #<%= $svcnum %>
<BR>Service: <B><%= $part_svc->svc %></B>
<BR>Domain name: <B><%= $domain %></B>
<BR>Catch all email <A HREF="<%= ${p} %>misc/catchall.cgi?<%= $svcnum %>">(change)</A>:
<%= $email ? "<B>$email</B>" : "<I>(none)<I>" %>
<BR><BR><A HREF="<%= ${p} %>misc/whois.cgi?custnum=<%=$custnum%>;svcnum=<%=$svcnum%>;domain=<%=$domain%>">View whois information.</A>
<BR><BR>
<SCRIPT>
  function areyousure(href) {
    if ( confirm("Remove this record?") == true )
      window.location.href = href;
  }
</SCRIPT>

<% my @records; if ( @records = $svc_domain->domain_record ) { %>
  <%= ntable("",2) %>
  <tr><th>Zone</th><th>Type</th><th>Data</th></tr>

  <% foreach my $domain_record ( @records ) {
       my $type = $domain_record->rectype eq '_mstr'
                    ? "(slave)"
                    : $domain_record->recaf. ' '. $domain_record->rectype;
  %>

    <tr><td><%= $domain_record->reczone %></td>
    <td><%= $type %></td>
    <td><%= $domain_record->recdata %>

    <% unless ( $domain_record->rectype eq 'SOA' ) { %>
      (<A HREF="javascript:areyousure('<%=$p%>misc/delete-domain_record.cgi?<%=$domain_record->recnum%>')">delete</A>)
    <% } %>
    </td></tr>
  <% } %>
  </table>
<% } %>

<BR>
<FORM METHOD="POST" ACTION="<%=$p%>edit/process/domain_record.cgi">
<INPUT TYPE="hidden" NAME="svcnum" VALUE="<%=$svcnum%>">
<INPUT TYPE="text" NAME="reczone"> 
<INPUT TYPE="hidden" NAME="recaf" VALUE="IN"> IN 
 <SELECT NAME="rectype">
<% foreach (qw( A NS CNAME MX PTR) ) { %>
  <OPTION VALUE="<%=$_%>"><%=$_%></OPTION>
<% } %>
 </SELECT>
<INPUT TYPE="text" NAME="recdata"> <INPUT TYPE="submit" VALUE="Add record">
</FORM><BR><BR>or<BR><BR>
<FORM METHOD="POST" ACTION="<%=$p%>edit/process/domain_record.cgi">
<INPUT TYPE="hidden" NAME="svcnum" VALUE="<%=$svcnum%>">

<% if ( @records ) { %> Delete all records and <% } %>
Slave from nameserver IP 
<INPUT TYPE="hidden" NAME="svcnum" VALUE="<%=$svcnum%>">
<INPUT TYPE="hidden" NAME="reczone" VALUE="@"> 
<INPUT TYPE="hidden" NAME="recaf" VALUE="IN">
<INPUT TYPE="hidden" NAME="rectype" VALUE="_mstr">
<INPUT TYPE="text" NAME="recdata"> <INPUT TYPE="submit" VALUE="Slave domain">
</FORM>
<BR><BR><%= joblisting({'svcnum'=>$svcnum}, 1) %>
</BODY></HTML>
