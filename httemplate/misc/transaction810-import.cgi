<% include("/elements/header.html",'Batch Customer Import') %>

<FORM ACTION="process/transaction810-import.cgi" METHOD="post" ENCTYPE="multipart/form-data">

Import a CSV file containing 810 data.
<BR><BR>

<!-- Simple file format is CSV, with the following field order: <i>duns, inv_num, 867_usage, esiid, tdsp, due_date, inv_date, usage_kwatts, srvc_from_date, srvc_to_date, puct_fund, billed_demand, measure_demand, bill_status, billing_type, 997_ack</i>
<BR><BR> -->

Extended file format is CSV, with the 
<BR><BR>

<%$req%> Required fields
<BR><BR>

[1] This field has special treatment upon import: If a string is passed instead
of an integer, the string is searched for and if necessary auto-created in the
target table.
<BR><BR>

[2] <i>username</i> and <i>_password</i> are required if <i>pkgpart</i> is specified.
<BR><BR>

<% &ntable("#cccccc") %>

<% include('/elements/tr-select-agent.html', '', #$agentnum,
              'label'       => "<B>Agent</B>",
              'empty_label' => 'Select agent',
           )
%>

<TR>
  <TH ALIGN="right">Format</TH>
  <TD>
    <SELECT NAME="format">
<!--      <OPTION VALUE="simple">Simple -->
      <OPTION VALUE="extended" SELECTED>Extended
    </SELECT>
  </TD>
</TR>

<TR>
  <TH ALIGN="right">CSV filename</TH>
  <TD><INPUT TYPE="file" NAME="csvfile"></TD>
</TR>
% #include('/elements/tr-select-part_referral.html')
%


<!--
<TR>
  <TH>First package</TH>
  <TD>
    <SELECT NAME="pkgpart"><OPTION VALUE="">(none)</OPTION>
% foreach my $part_pkg ( qsearch('part_pkg',{'disabled'=>'' }) ) { 

       <OPTION VALUE="<% $part_pkg->pkgpart %>"><% $part_pkg->pkg. ' - '. $part_pkg->comment %></OPTION>
% } 

    </SELECT>
  </TD>
</TR>
-->

</TABLE>
<BR><BR>

<INPUT TYPE="submit" VALUE="Import">
</FORM>

<% include('/elements/footer.html') %>

<%once>
my $req = qq!<font color="#ff0000">*</font>!;
</%once>
