<% include("/elements/header.html",'Batch Customer Import') %>

Import a CSV file containing customer records.
<BR><BR>

<FORM ACTION="process/cust_main-import.cgi" METHOD="post" ENCTYPE="multipart/form-data">

<% &ntable("#cccccc", 2) %>

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

<TR><TD COLSPAN=2 ALIGN="center" STYLE="padding-top:6px"><INPUT TYPE="submit" VALUE="Import CSV file"></TD></TR>

</TABLE>

</FORM>

<BR>

<!-- Simple file format is CSV, with the following field order: <i>cust_pkg.setup, dayphone, first, last, address1, address2, city, state, zip, comments</i>
<BR><BR> -->

Extended file format is CSV, with the following field order: <i>agent_custid, refnum<%$req%>, last<%$req%>, first<%$req%>, address1<%$req%>, address2, city<%$req%>, state<%$req%>, zip<%$req%>, country, daytime, night, ship_last, ship_first, ship_address1, ship_address2, ship_city, ship_state, ship_zip, ship_country, payinfo<%$req%>, paycvv, paydate<%$req%>, invoicing_list, pkgpart, username, _password</i>
<BR><BR>

<%$req%> Required fields
<BR><BR>

Field information:

<ul>

  <li><i>agent_custid</i>: This is the reseller's idea of the customer number or identifier.  It may be left blank.  If specified, it must be unique per-agent.

  <li><i>refnum</i>: Advertising source number - where a customer heard about your service.  Configuration -&gt; Miscellaneous -&gt; View/Edit advertising sources.  This field has special treatment upon import: If a string is passed instead
of an integer, the string is searched for and if necessary auto-created in the
advertising source table.

  <li><i>payinfo</i>: Credit card number, or leave this, <i>paycvv</i> and <i>paydate</i> blank for email/paper invoicing.

  <li><i>paycvv</i>: CVV2 number (three digits on the back of the credit card)

  <li><i>paydate</i>: Credit card expiration date.

  <li><i>invoicing_list</i>: Email address for invoices, or POST for postal invoices.

  <li><i>pkgpart</i>: Package definition.  Configuration -&gt; Provisioning, services and packages -&gt; View/Edit package definitions

  <li><i>username</i> and <i>_password</i> are required if <i>pkgpart</i> is specified.
</ul>

<BR>

<% include('/elements/footer.html') %>

<%once>
my $req = qq!<font color="#ff0000">*</font>!;
</%once>
