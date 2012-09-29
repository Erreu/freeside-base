%if ( $error ) {
%  $cgi->param('error', $error);
<% $cgi->redirect(popurl(2). "svc_acct.cgi?". $cgi->query_string ) %>
%} else {
<% $cgi->redirect(popurl(3). "view/svc_acct.cgi?" . $svcnum ) %>
%}
<%init>
use CGI::Carp;
die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Provision customer service'); #something else more specific?

$cgi->param('svcnum') =~ /^(\d*)$/ or die "Illegal svcnum!";
my $svcnum = $1;

my $old;
if ( $svcnum ) {
  $old = qsearchs('svc_acct', { 'svcnum' => $svcnum } )
    or die "fatal: can't find account (svcnum $svcnum)!";
} else {
  $old = '';
}

#unmunge popnum
$cgi->param('popnum', (split(/:/, $cgi->param('popnum') ))[0] );

#unmunge usergroup
$cgi->param('usergroup', [ $cgi->param('radius_usergroup') ] );

#unmunge bytecounts
foreach (map { $_,$_."_threshold" } qw( upbytes downbytes totalbytes )) {
  $cgi->param($_, FS::UI::bytecount::parse_bytecount($cgi->param($_)) );
}

#unmunge cgp_accessmodes (falze laziness-ish w/part_svc.pm::process &svc_domain)
unless ( $cgi->param('cgp_accessmodes') ) {
  $cgi->param('cgp_accessmodes', 
    join(' ',
      sort map { /^cgp_accessmodes_([\w\/]+)$/ or die "no way"; $1; }
               grep $cgi->param($_),
                    grep /^cgp_accessmodes_([\w\/]+)$/,
                         $cgi->param()
        )
  );
}

my %hash = $svcnum ? $old->hash : ();
for ( fields('svc_acct'), qw( pkgnum svcpart usergroup ) ) {
    $hash{$_} = scalar($cgi->param($_));
}
if ( $svcnum ) {
  for ( grep $old->$_, qw( cf_privatekey ) ) {
    $hash{$_} = $old->$_;
  }
}
my $new = new FS::svc_acct ( \%hash );

my $error = '';

my $part_svc = $svcnum ? 
                $old->part_svc : 
                qsearchs( 'part_svc', 
                  { 'svcpart' => $cgi->param('svcpart') }
                );

# google captcha auth
if ( $cgi->param('captcha_response') ) {
  my ($export) = $part_svc->part_export('acct_google');
  if ( $export and
      ! $export->captcha_auth($cgi->param('captcha_response')) ) { 
    $error = 'Re-enter the security word.';
  }
}

$new->_password($old->_password) if $old;
if (     $cgi->param('clear_password') eq '*HIDDEN*'
      || $cgi->param('clear_password') =~ /^\(.* encrypted\)$/ ) {
  die "fatal: no previous account to recall hidden password from!" unless $old;
} else {
  $error ||= $new->set_password($cgi->param('clear_password'));
}

if ( ! $error ) {

  my $export_info = FS::part_export::export_info();

  my @svc_export_machine =
    map FS::svc_export_machine->new({
          'svcnum'     => $svcnum,
          'exportnum'  => $_->exportnum,
          'machinenum' => scalar($cgi->param('exportnum'.$_->exportnum.'machinenum')),
        }),
      grep { $_->machine eq '_SVC_MACHINE' }
        $part_svc->part_export;

  if ( $svcnum ) {
    foreach ( grep { $old->$_ != $new->$_ }
                   qw( seconds upbytes downbytes totalbytes )
            )
    {
      my %hash = map { $_ => $new->$_ } 
                 grep { $new->$_ }
                 qw( seconds upbytes downbytes totalbytes );

      $error ||= "invalid $_" foreach grep { $hash{$_} !~ /^-?\d+$/ } keys %hash;
      $error ||= $new->set_usage(\%hash);  #unoverlimit and trigger radius changes
      last;                                #once is enough
    }
    $error ||= $new->replace($old, 'child_objects'=>\@svc_export_machine);
  } else {
    $error ||= $new->insert('child_objects'=>\@svc_export_machine);
    $svcnum = $new->svcnum;
  }
}

</%init>
