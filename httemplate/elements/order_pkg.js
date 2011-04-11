function enable_order_pkg () {
  var form = document.OrderPkgForm;
  var discountnum = form.discountnum;

  if ( form.pkgpart.selectedIndex > 0 ) {
    form.submitButton.disabled = false;
    if ( discountnum ) {
      if ( form.pkgpart.options[form.pkgpart.selectedIndex].getAttribute('data-can_discount') == 1 ) {
        form.discountnum.disabled = false;
      } else {
        form.discountnum.disabled = true;
      }
    }
  } else {
    form.submitButton.disabled = true;
    if ( discountnum ) { form.discountnum.disabled = true; }
  }
}

function standardize_new_location() {
  var form = document.OrderPkgForm;
  var loc = form.locationnum;
  if (loc.type == 'select-one' && loc.options[loc.selectedIndex].value == -1){
    standardize_locations();
  } else {
    form.submit();
  }
}
