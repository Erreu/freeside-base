<% include( 'elements/search.html',
                  'html_init'   => $html_init, 
                  'title'       => 'Package Search Results', 
                  'name'        => 'packages',
                  'query'       => $sql_query,
                  'count_query' => $count_query,
                  #'redirect'    => $link,
                  'header'      => [ '#',
                                     'Package',
                                     'Class',
                                     'Status',
                                     'Freq.',
                                     'Setup',
                                     'Last bill',
                                     'Next bill',
                                     'Adjourn',
                                     'Susp.',
                                     'Expire',
                                     'Cancel',
                                     'Reason',
                                     FS::UI::Web::cust_header(
                                       $cgi->param('cust_fields')
                                     ),
                                     'Services',
                                   ],
                  'fields'      => [
                    'pkgnum',
                    sub { #my $part_pkg = $part_pkg{shift->pkgpart};
                          #$part_pkg->pkg; # ' - '. $part_pkg->comment;
                          $_[0]->pkg; # ' - '. $_[0]->comment;
                        },
                    'classname',
                    sub { ucfirst(shift->status); },
                    sub { #shift->part_pkg->freq_pretty;

                          #my $part_pkg = $part_pkg{shift->pkgpart};
                          #$part_pkg->freq_pretty;

                          FS::part_pkg::freq_pretty(shift);
                        },

                    #sub { time2str('%b %d %Y', shift->setup); },
                    #sub { time2str('%b %d %Y', shift->last_bill); },
                    #sub { time2str('%b %d %Y', shift->bill); },
                    #sub { time2str('%b %d %Y', shift->susp); },
                    #sub { time2str('%b %d %Y', shift->expire); },
                    #sub { time2str('%b %d %Y', shift->get('cancel')); },
                    ( map { time_or_blank($_) }
                          qw( setup last_bill bill adjourn susp expire cancel ) ),

                    sub { my $self = shift;
                          my $return = '';
                          if ($self->getfield('cancel') ||
                            $self->getfield('suspend')) {
                              my $reason = $self->last_reason;# too inefficient?
                              $return = $reason->reason if $reason;

                          }
                          $return;
                        },

                    \&FS::UI::Web::cust_fields,
                    #sub { '<table border=0 cellspacing=0 cellpadding=0 STYLE="border:none">'.
                    #      join('', map { '<tr><td align="right" style="border:none">'. $_->[0].
                    #                     ':</td><td style="border:none">'. $_->[1]. '</td></tr>' }
                    #                   shift->labels
                    #          ).
                    #      '</table>';
                    #    },
                    sub {
                          [ map {
                                  [ 
                                    { 'data' => $_->[0]. ':',
                                      'align'=> 'right',
                                    },
                                    { 'data' => $_->[1],
                                      'align'=> 'left',
                                      'link' => $p. 'view/' .
                                                $_->[2]. '.cgi?'. $_->[3],
                                    },
                                  ];
                                } shift->labels
                          ];
                        },
                  ],
                  'color' => [
                    '',
                    '',
                    '',
                    sub { shift->statuscolor; },
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    FS::UI::Web::cust_colors(),
                    '',
                  ],
                  'style' => [ '', '', '', 'b', '', '', '', '', '', '', '',
                               FS::UI::Web::cust_styles() ],
                  'size'  => [ '', '', '', '-1', ],
                  'align' => 'rllclrrrrrr'. FS::UI::Web::cust_aligns(). 'r',
                  'links' => [
                    $link,
                    $link,
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    ( map { $_ ne 'Cust. Status' ? $clink : '' }
                          FS::UI::Web::cust_header(
                                                    $cgi->param('cust_fields')
                                                  )
                    ),
                    '',
                  ],
                  'extra_choices_callback'=> $extra_choices, 
              )
%>
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('List packages');

# my %part_pkg = map { $_->pkgpart => $_ } qsearch('part_pkg', {});


my %search_hash = ();

$search_hash{'query'} = $cgi->keywords;

for my $param (qw(agentnum magic status classnum pkgpart)) {
  $search_hash{$param} = $cgi->param($param)
    if $cgi->param($param);
}

###
# parse dates
###

#false laziness w/report_cust_pkg.html
my %disable = (
  'all'             => {},
  'one-time charge' => { 'last_bill'=>1, 'bill'=>1, 'adjourn'=>1, 'susp'=>1, 'expire'=>1, 'cancel'=>1, },
  'active'          => { 'susp'=>1, 'cancel'=>1 },
  'suspended'       => { 'cancel' => 1 },
  'cancelled'       => {},
  ''                => {},
);

foreach my $field (qw( setup last_bill bill adjourn susp expire cancel )) {

  my($beginning, $ending) = FS::UI::Web::parse_beginning_ending($cgi, $field);

  next if $beginning == 0 && $ending == 4294967295
       or $disable{$cgi->param('status')}->{$field};

  $search_hash{$field} = [ $beginning, $ending ];

}

my $sql_query = FS::cust_pkg->search_sql(\%search_hash);
my $count_query = delete($sql_query->{'count_query'});

my $link = sub {
  [ "${p}view/cust_main.cgi?".shift->custnum.'#cust_pkg', 'pkgnum' ];
};

my $clink = sub {
  my $cust_pkg = shift;
  $cust_pkg->cust_main_custnum
    ? [ "${p}view/cust_main.cgi?", 'custnum' ] 
    : '';
};

#if ( scalar(@cust_pkg) == 1 ) {
#  print $cgi->redirect("${p}view/cust_main.cgi?". $cust_pkg[0]->custnum.
#                       "#cust_pkg". $cust_pkg[0]->pkgnum );

#    my @cust_svc = qsearch( 'cust_svc', { 'pkgnum' => $pkgnum } );
#    my $rowspan = scalar(@cust_svc) || 1;

#    my $n2 = '';
#    foreach my $cust_svc ( @cust_svc ) {
#      my($label, $value, $svcdb) = $cust_svc->label;
#      my $svcnum = $cust_svc->svcnum;
#      my $sview = $p. "view";
#      print $n2,qq!<TD><A HREF="$sview/$svcdb.cgi?$svcnum"><FONT SIZE=-1>$label</FONT></A></TD>!,
#            qq!<TD><A HREF="$sview/$svcdb.cgi?$svcnum"><FONT SIZE=-1>$value</FONT></A></TD>!;
#      $n2="</TR><TR>";
#    }

sub time_or_blank {
   my $column = shift;
   return sub {
     my $record = shift;
     my $value = $record->get($column); #mmm closures
     $value ? time2str('%b %d %Y', $value ) : '';
   };
}

my $html_init = '';
for (qw (overlibmws overlibmws_iframe overlibmws_draggable iframecontentmws))
{
  $html_init .=
    qq!<SCRIPT TYPE="text/javascript" SRC="$fsurl/elements/$_.js"></SCRIPT>!;
}

my $extra_choices = sub {
  my $query = shift;
  my $choices = '';

  my $url = qq!overlib( OLiframeContent('!. popurl(2).
            qq!misc/bulk_change_pkg.cgi?$query', 768, 336, !.
            qq!'bulk_pkg_change_popup' ), CAPTION, 'Change Packages'!.
            qq!, STICKY, AUTOSTATUSCAP, MIDX, 0, MIDY, 0, DRAGGABLE, !.
            qq!CLOSECLICK ); return false;!;

  if ($FS::CurrentUser::CurrentUser->access_right('Bulk change customer packages')) {
    $choices .= qq!<BR><A HREF="javascript:void(0);"!.
                qq!onClick="$url">Change these packages</A>!;
  }

  return $choices;
};

</%init>
