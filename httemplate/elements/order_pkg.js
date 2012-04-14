function pkg_changed () {
  var form = document.OrderPkgForm;
  var discountnum = form.discountnum;

  if ( form.pkgpart.selectedIndex > 0 ) {

    form.submitButton.disabled = false;
    if ( discountnum ) {
      if ( form.pkgpart.options[form.pkgpart.selectedIndex].getAttribute('data-can_discount') == 1 ) {
        form.discountnum.disabled = false;
        discountnum_changed(form.discountnum);
      } else {
        form.discountnum.disabled = true;
        discountnum_changed(form.discountnum);
      }
    }

    if ( form.pkgpart.options[form.pkgpart.selectedIndex].getAttribute('data-can_start_date') == 1 ) {
      form.start_date_text.disabled = false;
      form.start_date.style.backgroundColor = '#ffffff';
      form.start_date_button.style.display = '';
    } else {
      form.start_date_text.disabled = true;
      form.start_date.style.backgroundColor = '#dddddd';
      form.start_date_button.style.display = 'none';
    }

  } else {
    form.submitButton.disabled = true;
    if ( discountnum ) { form.discountnum.disabled = true; }
    discountnum_changed(form.discountnum);
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

function submit_abort() {
  document.OrderPkgForm.submitButton.disabled = false;
}
