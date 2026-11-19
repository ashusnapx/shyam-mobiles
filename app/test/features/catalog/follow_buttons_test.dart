import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/format.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/widgets/blocks.dart';

StoreSettings _settings({String? ig, String? fb}) => StoreSettings(
      deliveryFeePaise: 0,
      freeDeliveryMinPaise: 0,
      codEnabled: false,
      codMaxPaise: 0,
      storePhone: '+917987559272',
      storeAddress: 'Waidhan',
      repairNote: '',
      instagramHandle: ig,
      facebookHandle: fb,
    );

void main() {
  test('SocialSite: a pasted link or @handle becomes the bare handle, and the link is built from it', () {
    const ig = SocialSite.instagram, fb = SocialSite.facebook;
    expect(ig.bare(' @ashusnapx '), 'ashusnapx');
    expect(ig.bare('https://www.instagram.com/ashusnapx/?igsh=x'), 'ashusnapx');
    expect(ig.bare('instagram.com/ashu.snap_x'), 'ashu.snap_x');
    expect(fb.bare('https://m.facebook.com/ashusnapx?ref=x'), 'ashusnapx');
    expect(fb.bare('fb.com/ashusnapx'), 'ashusnapx');
    expect(ig.valid(ig.bare('https://facebook.com/ashusnapx')), isFalse, reason: "another site's link");
    expect(fb.valid(fb.bare('https://facebook.com')), isFalse, reason: 'no page in it');
    expect(ig.valid('ashu snap'), isFalse);
    expect(ig.valid('a' * 30), isTrue);
    expect(ig.valid('a' * 31), isFalse);
    expect(fb.valid('shy_m'), isFalse, reason: 'no underscores on Facebook');
    expect(fb.valid('shy.m'), isTrue);
    expect(fb.valid('shym'), isFalse, reason: '5 or more');
    expect(ig.url('ashusnapx').toString(), 'https://instagram.com/ashusnapx');
    expect(fb.url('ashusnapx').toString(), 'https://facebook.com/ashusnapx');
  });

  testWidgets('Follow buttons: one per saved handle, none at all without', (tester) async {
    Future<void> pump(StoreSettings s) => tester.pumpWidget(MaterialApp(home: Scaffold(body: FollowButtons(s))));
    await pump(_settings());
    expect(find.text('Follow the shop'), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    await pump(_settings(ig: 'ashusnapx'));
    expect(find.byTooltip('Shyam Mobiles on Instagram'), findsOneWidget);
    expect(find.byTooltip('Shyam Mobiles on Facebook'), findsNothing);

    await pump(_settings(ig: 'ashusnapx', fb: 'ashusnapx'));
    expect(find.byTooltip('Shyam Mobiles on Instagram'), findsOneWidget);
    expect(find.byTooltip('Shyam Mobiles on Facebook'), findsOneWidget);
  });
}
