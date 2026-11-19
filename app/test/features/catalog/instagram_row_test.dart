import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/catalog/data/social_repository.dart';
import 'package:shyam_mobiles/features/catalog/widgets/instagram_row.dart';

void main() {
  test('a post needs a thumbnail and an https instagram.com link (the Cloud Function shape)', () {
    final ok = InstagramPost.fromJson({
      'id': '1',
      'mediaUrl': null,
      'thumbUrl': 'https://cdn/1.jpg',
      'permalink': 'https://www.instagram.com/p/1/',
      'caption': 'New stock',
      'mediaType': 'VIDEO',
      'takenAt': DateTime(2026, 11),
    });
    expect(ok?.mediaType, 'VIDEO');
    expect(ok?.caption, 'New stock');
    expect(InstagramPost.fromJson({'id': '2', 'thumbUrl': 'https://cdn/2.jpg', 'permalink': 'https://evil.example/p/2'}), isNull);
    expect(InstagramPost.fromJson({'id': '3', 'permalink': 'https://www.instagram.com/p/3/'}), isNull);
  });

  testWidgets('From our Instagram: hidden when there are no posts, a tile per post otherwise', (tester) async {
    Future<void> pump(List<InstagramPost> posts) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [instagramPostsProvider.overrideWith((ref) async => posts)],
        child: const MaterialApp(home: Scaffold(body: InstagramRow())),
      ));
      await tester.pump();
    }

    await pump(const []);
    expect(find.text('From our Instagram'), findsNothing);

    await pump(const [
      InstagramPost(id: '1', thumbUrl: 'https://cdn/1.jpg', permalink: 'https://www.instagram.com/p/1/', caption: 'New stock'),
      InstagramPost(id: '2', thumbUrl: 'https://cdn/2.jpg', permalink: 'https://www.instagram.com/p/2/', mediaType: 'VIDEO'),
    ]);
    expect(find.text('From our Instagram'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
  });
}
