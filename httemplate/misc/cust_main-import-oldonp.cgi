<% include("/elements/header.html",'Batch Customer Import') %>

<FORM ACTION="process/cust_main-import-oldonp.cgi" METHOD="post" ENCTYPE="multipart/form-data">

Import a CSV file containing customer records.
<BR><BR>

<!-- Simple file format is CSV, with the following field order: <i>cust_pkg.setup, dayphone, first, last, address1, address2, city, state, zip, comments</i>
<BR><BR> -->

Extended file format is CSV, with the following field order: <i>custnum<%$req%>, last<%$req%>, first<%$req%>, address1<%$req%>, address2, city state<%$req%>, zip<%$req%>, ss, daytime ph#, nightime ph#, service_lastname<%$req%>, service_firstname<%$req%>, service_address1<%$req%>, service_address2, service_city service_state <%$req%>, service_zip<%$req%>, newcustdate<%$req%></i>
<BR><BR>

<%$req%> Required fields
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
