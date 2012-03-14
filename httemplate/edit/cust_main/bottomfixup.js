<%init>
my %opt = @_; # custnum
my $conf = new FS::Conf;

my $company_latitude  = $conf->config('company_latitude');
my $company_longitude = $conf->config('company_longitude');

my @fixups = ('copy_payby_fields', 'standardize_locations');

#push @fixups, 'fetch_censustract'
#    if $conf->exists('cust_main-require_censustract');

push @fixups, 'check_unique'
    if $conf->exists('cust_main-check_unique') and !$opt{'custnum'};

push @fixups, 'do_submit'; # always last
</%init>

var fixups = <% encode_json(\@fixups) %>;
var fixup_position;
var running = false;

%# state machine to deal with all the asynchronous stuff we're doing
%# call this after each fixup on success:
function submit_continue() {
  if ( running ) {
    window[ fixups[fixup_position++] ].call();
  }
}

%# or on failure:
function submit_abort() {
  running = false;
  fixup_position = 0;
  document.CustomerForm.submitButton.disabled = false;
  cClick();
}

function bottomfixup(what) {
  fixup_position = 0;
  document.CustomerForm.submitButton.disabled = true;
  running = true;
  submit_continue();
}

function do_submit() {
  document.CustomerForm.submit();
}

function copy_payby_fields() {
  var layervars = new Array(
    'payauto', 'billday',
    'payinfo', 'payinfo1', 'payinfo2', 'payinfo3', 'paytype',
    'payname', 'paystate', 'exp_month', 'exp_year', 'paycvv',
    'paystart_month', 'paystart_year', 'payissue',
    'payip',
    'paid'
  );

  var cf = document.CustomerForm;
  var payby = cf.payby.options[cf.payby.selectedIndex].value;
  for ( f=0; f < layervars.length; f++ ) {
    var field = layervars[f];
    copyelement( cf.elements[payby + '_' + field],
                 cf.elements[field]
               );
  }
  submit_continue();
}

<% include( '/elements/standardize_locations.js',
            'callback' => 'submit_continue();'
          )
%>

function copyelement(from, to) {
  if ( from == undefined ) {
    to.value = '';
  } else if ( from.type == 'select-one' ) {
    to.value = from.options[from.selectedIndex].value;
    //alert(from + " (" + from.type + "): " + to.name + " => (" + from.selectedIndex + ") " + to.value);
  } else if ( from.type == 'checkbox' ) {
    if ( from.checked ) {
      to.value = from.value;
    } else {
      to.value = '';
    }
  } else {
    if ( from.value == undefined ) {
      to.value = '';
    } else {
      to.value = from.value;
    }
  }
  //alert(from + " (" + from.type + "): " + to.name + " => " + to.value);
}

function check_unique() {
  var search_hash = new Object;
% foreach ($conf->config('cust_main-check_unique')) {
  search_hash['<% $_ %>'] = document.CustomerForm.elements['<% $_ %>'].value;
% }

%# supported in IE8+, Firefox 3.5+, WebKit, Opera 10.5+
  duplicates_form(JSON.stringify(search_hash), confirm_unique);
}

function confirm_unique(arg) {
  if ( arg.match(/\S/) ) {
%# arg contains a complete form to choose an existing customer, or not
  overlib( arg, CAPTION, 'Duplicate customer', STICKY, AUTOSTATUSCAP, 
      CLOSETEXT, '', MIDX, 0, MIDY, 0, DRAGGABLE, WIDTH, 576, HEIGHT, 
      268, BGCOLOR, '#333399', CGCOLOR, '#333399', TEXTSIZE, 3 );
  } else { // no duplicates
    submit_continue();
  }
}

