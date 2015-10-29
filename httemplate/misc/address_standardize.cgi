<% encode_json($return) %>\
<%init>

local $SIG{__DIE__}; #disable Mason error trap

my $DEBUG = 0;

my $conf = new FS::Conf;

# figure out the prefix
my $pre;
foreach my $name ($cgi->param) {
  if ($name =~ /^(\w*)address1$/) {
    $pre = $1;
    last;
  }
}
die "no address1 field in location" if !defined($pre);

# gather relevant fields
my %old = ( map { $_ => scalar($cgi->param($pre . $_)) }
  qw( company address1 address2 city state zip country )
);

my $cache = eval { FS::GeocodeCache->standardize(\%old) };
$cache->set_coord;
# don't do set_censustract here, though censustract may be set by now

# give the fields their prefixed names back
# except always name the error string 'error'
my $error = delete($cache->{'error'}) || '';
my %new = (
  'changed' => 0,
  'error' => $error,
  map { $pre.$_, $cache->get($_) } keys %$cache
);

foreach ( qw(address1 address2 city state zip country) ) {
  if ( $new{$pre.$_} ne $old{$pre.$_} ) {
    $new{changed} = 1;
    last;
  }
}

# refold this to make it acceptable to jquery
#my $return = [ map { { name => $_, value => $new{$_} } } keys %new ];
my $return = \%new;
warn "result:\n".encode_json($return) if $DEBUG;

$r->content_type('application/json');
</%init>
