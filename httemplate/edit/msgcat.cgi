<!-- mason kludge -->
<%

print header("Edit Message catalog", menubar(
#  'Main Menu' => $p,
)), '<BR>';

print qq!<FONT SIZE="+1" COLOR="#ff0000">Error: !. $cgi->param('error').
      '</FONT><BR><BR>'
  if $cgi->param('error');

my $widget = new HTML::Widgets::SelectLayers(
  'selected_layer' => 'en_US',
  'options'        => { 'en_US'=>'en_US' },
  'form_action'    => 'process/msgcat.cgi',
  'layer_callback' => sub {
    my $layer = shift;
    my $html = qq!<INPUT TYPE="hidden" NAME="locale" VALUE="$layer">!.
               "<BR>Messages for locale $layer<BR>". table().
               "<TR><TH COLSPAN=2>Code</TH>".
               "<TH>Message</TH>";
    $html .= "<TH>en_US Message</TH>" unless $layer eq 'en_US';
    $html .= '</TR>';

    #foreach my $msgcat ( sort { $a->msgcode cmp $b->msgcode }
    #                       qsearch('msgcat', { 'locale' => $layer } ) ) {
    foreach my $msgcat ( qsearch('msgcat', { 'locale' => $layer } ) ) {
      $html .=
        '<TR><TD>'. $msgcat->msgnum. '</TD><TD>'. $msgcat->msgcode. '</TD>'.
        '<TD><INPUT TYPE="text" SIZE=32 '.
        qq! NAME="!. $msgcat->msgnum. '" '.
        qq!VALUE="!. ($cgi->param($msgcat->msgnum)||$msgcat->msg). qq!"></TD>!;
      unless ( $layer eq 'en_US' ) {
        my $en_msgcat = qsearchs('msgcat', {
          'locale'  => 'en_US',
          'msgcode' => $msgcat->msgcode,
        } );
        $html .= '<TD>'. $en_msgcat->msg. '</TD>';
      }
      $html .= '</TR>';
    }

    $html .= '</TABLE><BR><INPUT TYPE="submit" VALUE="Apply changes">';

    $html;
  },

);

print $widget->html;

print <<END;
    </TABLE>
  </BODY>
</HTML>
END

%>
