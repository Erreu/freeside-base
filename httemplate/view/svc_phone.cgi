<% include('elements/svc_Common.html',
              'table'     => 'svc_phone',
              'fields'    => \@fields,
              'labels'    => {
                               'countrycode'  => 'Country code',
                               'phonenum'     => 'Phone number',
                               'domain'       => 'Domain',
                               'pbx_title'    => 'PBX',
                               'sip_password' => 'SIP password',
                               'pin'          => 'PIN',
                               'phone_name'   => 'Name',
                             },
              'html_foot' => $html_foot,
          )
%>
<%init>

my $conf = new FS::Conf;
my $countrydefault = $conf->config('countrydefault') || 'US';

my @fields = qw( countrycode phonenum );
push @fields, 'domain' if $conf->exists('svc_phone-domain');
push @fields, qw( pbx_title sip_password pin phone_name );

my $html_foot = sub {
  my $svc_phone = shift;

  ###
  # E911 Info
  ###

  my $e911 = 
    'E911 Information'.
    &ntable("#cccccc"). '<TR><TD>'. ntable("#cccccc",2).
      '<TR><TD>Location</TD>'.
      '<TD BGCOLOR="#FFFFFF">'.
        $svc_phone->location_label( 'join_string'     => '<BR>',
                                    'double_space'    => ' &nbsp; ',
                                    'escape_function' => \&encode_entities,
                                    'countrydefault'  => $countrydefault,
                                  ).
      '</TD></TR>'.
    '</TABLE></TD></TR></TABLE>'.
    '<BR>'
  ;

  ###
  # Devices
  ###

  my $devices = '';

  my $sth = dbh->prepare("SELECT COUNT(*) FROM part_device") #WHERE disabled = '' OR disabled IS NULL;");
    or die dbh->errstr;
  $sth->execute or die $sth->errstr;
  my $num_part_device = $sth->fetchrow_arrayref->[0];

  my @phone_device = $svc_phone->phone_device;
  if ( @phone_device || $num_part_device ) {
    my $svcnum = $svc_phone->svcnum;
    $devices .=
      qq[Devices (<A HREF="${p}edit/phone_device.html?svcnum=$svcnum">Add device</A>)<BR>];
    if ( @phone_device ) {

      $devices .= qq!
        <SCRIPT>
          function areyousure(href) {
           if (confirm("Are you sure you want to delete this device?") == true)
             window.location.href = href;
          }
        </SCRIPT>
      !;


      $devices .= 
        include('/elements/table-grid.html').
          '<TR>'.
            '<TH CLASS="grid" BGCOLOR="#cccccc">Type</TH>'.
            '<TH CLASS="grid" BGCOLOR="#cccccc">MAC Addr</TH>'.
            '<TH CLASS="grid" BGCOLOR="#cccccc"></TH>'.
            '<TH CLASS="grid" BGCOLOR="#cccccc"></TH>'.
          '</TR>';
      my $bgcolor1 = '#eeeeee';
      my $bgcolor2 = '#ffffff';
      my $bgcolor = '';

      foreach my $phone_device ( @phone_device ) {

        if ( $bgcolor eq $bgcolor1 ) {
          $bgcolor = $bgcolor2;
        } else {
          $bgcolor = $bgcolor1;
        }
        my $td = qq(<TD CLASS="grid" BGCOLOR="$bgcolor">);

        my $devicenum = $phone_device->devicenum;
        my $export_links = join( '<BR>', @{ $phone_device->export_links } );

        $devices .= '<TR>'.
                      $td. $phone_device->part_device->devicename. '</TD>'.
                      $td. $phone_device->mac_addr. '</TD>'.
                      $td. $export_links. '</TD>'.
                      "$td( ".
                        qq(<A HREF="${p}edit/phone_device.html?$devicenum">edit</A> | ).
                        qq(<A HREF="javascript:areyousure('${p}misc/delete-phone_device.html?$devicenum')">delete</A>).
                      ' )</TD>'.
                    '</TR>';
      }
      $devices .= '</TABLE><BR>';
    }
    $devices .= '<BR>';
  }

  ##
  # CDR links
  ##

  tie my %what, 'Tie::IxHash',
    'pending' => 'NULL',
    'billed'  => 'done',
  ;

  #XXX src & charged party (& default prefix) as per voip_cdr.pm
  #XXX handle toll free too

  my $number = $svc_phone->phonenum;
  $number = $svc_phone->countrycode. $number
    unless $svc_phone->countrycode eq '1';

  #my @links = map {
  #  qq(<A HREF="${p}search/cdr.html?src=$number;freesidestatus=$what{$_}">).
  #  "View $_ CDRs</A>";
  #} keys(%what);
  my @links = map {
    qq(<A HREF="${p}search/cdr.html?cdrbatchnum=__ALL__;charged_party=$number;freesidestatus=$what{$_}">).
    "View $_ CDRs</A>";
  } keys(%what);

  my @ilinks = ( qq(<A HREF="${p}search/cdr.html?cdrbatchnum=__ALL__;dst=$number">).
                 'View incoming CDRs</A>' );

  ###
  # concatenate & return
  ###

  $e911.
  $devices.
  join(' | ', @links ). '<BR>'.
  join(' | ', @ilinks). '<BR>';

};

</%init>
