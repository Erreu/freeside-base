<%init>
my %opt = @_; # custnum
my $conf = new FS::Conf;

my $company_latitude  = $conf->config('company_latitude');
my $company_longitude = $conf->config('company_longitude');

my @fixups = (
    'copy_if_same',
    'copy_payby_fields',
    'standardize_locations',
    'confirm_censustract'
    );

push @fixups, 'confirm_censustract';

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

%# if "same as billing" is checked, ensure that the invisible ship location
%# fields are set to the values of the visible fields.
function copy_if_same() {
  var cf = document.CustomerForm;
  if ( cf.same.checked ) {
    var inputs = new Array(
        'address1', 'address2', 'location_type', 'location_number', 'zip',
        'latitude', 'longitude', 'coord_auto', 'geocode',
        // these are selects, not inputs, but per the spec this still works
        'city', 'county', 'state', 'country'
    );
    for ( var i = 0; i < inputs.length; i++ ) {
      if ( cf['bill_' + inputs[i]] != undefined ) {
        // because some of these fields don't always exist
        cf['ship_' + inputs[i]].value = cf['bill_' + inputs[i]].value;
      }
    }
    cf['ship_addr_clean'].checked = cf['bill_addr_clean'].checked;
  }
  // this can't really fail
  submit_continue();
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
            'callback' => 'submit_continue();',
            'main_prefix' => 'bill_',
            'no_company' => 1,
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

var prefix;

% # the value in 'censustract' is the confirmed censustract; if it's set,
% # do nothing here
function confirm_censustract() {
  prefix = document.getElementById('same').checked ? 'bill_' : 'ship_';
  var cf = document.CustomerForm;
  if ( cf.elements[prefix+'censustract'].value == '' ) {
    var address_info = form_address_info();
    address_info[prefix+'latitude']  = cf.elements[prefix+'latitude'].value;
    address_info[prefix+'longitude'] = cf.elements[prefix+'longitude'].value;
    OLpostAJAX(
        '<%$p%>/misc/confirm-censustract.html',
        'q=' + encodeURIComponent(JSON.stringify(address_info)),
        function() {
          overlib( OLresponseAJAX, CAPTION, 'Confirm censustract', STICKY,
            AUTOSTATUSCAP, CLOSETEXT, '', MIDX, 0, MIDY, 0, DRAGGABLE, WIDTH,
            576, HEIGHT, 268, BGCOLOR, '#333399', CGCOLOR, '#333399',
            TEXTSIZE, 3 );
        },
        0);
  } else submit_continue();
}

%# called from confirm-censustract.html
function set_censustract(tract, year) {
  var cf = document.CustomerForm;
  cf.elements[prefix+'censustract'].value = tract;
  cf.elements[prefix+'censusyear'].value = year;
  submit_continue();
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

