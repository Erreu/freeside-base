<% include('/elements/header-popup.html', "$action Customer Note") %>

<% include('/elements/error.html') %>

<FORM ACTION="<% popurl(1) %>process/cust_main_note.cgi" METHOD=POST>
<INPUT TYPE="hidden" NAME="custnum" VALUE="<% $custnum %>">
<INPUT TYPE="hidden" NAME="notenum" VALUE="<% $notenum %>">

<% include('/elements/htmlarea.html', 'field' => 'comment',
                                      'curr_value' => $comment) %>
% #<TEXTAREA NAME="comment" ROWS="12" COLS="60">
% # <% $comment %>
% #</TEXTAREA>

<BR><BR>
<INPUT TYPE="submit" VALUE="<% $notenum ? "Apply Changes" : "Add Note" %>">

</FORM>
</BODY>
</HTML>

<%init>

my $comment;
my $notenum = '';
if ( $cgi->param('error') ) {
  $comment     = $cgi->param('comment');
} elsif ( $cgi->param('notenum') =~ /^(\d+)$/ ) {
  $notenum = $1;
  die "illegal query ". $cgi->keywords unless $notenum;
  my $note = qsearchs('cust_main_note', { 'notenum' => $notenum });
  die "no such note: ". $notenum unless $note;
  $comment = $note->comments;
}

$comment =~ s/\r//g; # remove weird line breaks to protect FCKeditor

$cgi->param('custnum') =~ /^(\d+)$/ or die "illeagl custnum";
my $custnum = $1;

my $action = $notenum ? 'Edit' : 'Add';

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right("$action customer note");

</%init>

