import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider;

/// One post of social/instagram (firebase/functions/src/social/flows.ts toPosts). [thumbUrl] is set for every kind,
/// a video's cover included; mediaUrl and takenAt aren't shown, so they aren't read.
class InstagramPost {
  const InstagramPost({required this.id, required this.thumbUrl, required this.permalink, this.caption = '', this.mediaType = 'IMAGE'});

  final String id;
  final String thumbUrl;
  final String permalink;
  final String caption;
  final String mediaType; // IMAGE, VIDEO, CAROUSEL_ALBUM

  /// Null for an item without a thumbnail, or whose link isn't an https instagram.com page.
  static InstagramPost? fromJson(Map<String, dynamic> j) {
    final link = Uri.tryParse(j['permalink'] as String? ?? '');
    final thumb = j['thumbUrl'] as String?;
    if (thumb == null || link == null || link.scheme != 'https' || !link.host.endsWith('instagram.com')) return null;
    return InstagramPost(
      id: '${j['id']}',
      thumbUrl: thumb,
      permalink: link.toString(),
      caption: j['caption'] as String? ?? '',
      mediaType: j['mediaType'] as String? ?? 'IMAGE',
    );
  }
}

/// The shop's latest Instagram posts for Home.
abstract interface class SocialRepository {
  Future<List<InstagramPost>> instagramPosts();
}

/// social/instagram ({posts: [...], updatedAt}), written by a Cloud Function; everyone reads it.
class FirebaseSocialRepository implements SocialRepository {
  const FirebaseSocialRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<List<InstagramPost>> instagramPosts() async {
    final posts = (await _db.doc('social/instagram').get()).data()?['posts'] as List? ?? const [];
    return [for (final p in posts.whereType<Map>()) ?InstagramPost.fromJson(Map<String, dynamic>.from(p))];
  }
}

/// The Supabase build has no Instagram feed.
class SupabaseSocialRepository implements SocialRepository {
  const SupabaseSocialRepository();

  @override
  Future<List<InstagramPost>> instagramPosts() async => const [];
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) =>
    backend == Backend.firebase ? FirebaseSocialRepository(ref.watch(firestoreProvider)) : const SupabaseSocialRepository());

/// Empty when it fails too: Home just leaves the row out.
final instagramPostsProvider = FutureProvider<List<InstagramPost>>((ref) async {
  try {
    return await ref.watch(socialRepositoryProvider).instagramPosts();
  } catch (_) {
    return const [];
  }
});
