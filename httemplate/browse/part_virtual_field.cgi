<%= header('Virtual field definitions', menubar('Main Menu'   => $p)) %>
<%

my %pvfs;
my $block;
my $p2 = popurl(2);
my $dbtable;

foreach (qsearch('part_virtual_field', {})) {
  push @{ $pvfs{$_->dbtable} }, $_;
}
%>

<% if ($cgi->param('error')) { %>
   <FONT SIZE="+1" COLOR="#ff0000">Error: <%=$cgi->param('error')%></FONT>
   <BR><BR>
<% } %>

<A HREF="<%=$p2%>edit/part_virtual_field.cgi"><I>Add a new field</I></A><BR><BR>

<% foreach $dbtable (sort { $a cmp $b } keys (%pvfs)) { %>
<H3><%=$dbtable%></H3>

<%=table()%>
<TH><TD>Field name</TD><TD>Description</TD></TH>
<% foreach my $pvf (sort {$a->name cmp $b->name} @{ $pvfs{$dbtable} }) { %>
  <TR>
    <TD></TD>
    <TD>
      <A HREF="<%=$p2%>edit/part_virtual_field.cgi?<%=$pvf->vfieldpart%>">
        <%=$pvf->name%></A></TD>
    <TD><%=$pvf->label%></TD>
  </TR>
<%   } %>
</TABLE>
<% } %>
</BODY>
</HTML>

