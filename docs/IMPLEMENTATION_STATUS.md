# Social RPCs Implementation - Backend

## ✅ Implementado (Joaozinho)

### Migration: `20260919310000_social_schema.sql`
- Table `follows`: follower_id, following_id (unique constraint)
- Table `comments`: post_id, user_id, text, likes
- Table `comment_likes`: comment_id, user_id (for like tracking)
- Table `notifications`: user_id, type, title, body, actor_id, post_id, place_id, read
- Indexes for performance on all tables
- Added columns to `profiles`: followers_count, following_count, posts_count, bio

### Migration: `20260919320000_social_rpcs.sql`
- `get_user_profile(p_user_id)`: Fetch user profile with real follower/following counts
- `get_user_stats(p_user_id)`: Calculate real stats (sessions, minutes, meters, streak, posts)
- `follow_user(p_follower_id, p_following_id)`: Follow a user and update counters
- `unfollow_user(p_follower_id, p_following_id)`: Unfollow a user and update counters
- `is_following(p_follower_id, p_following_id)`: Check if user follows another
- `list_comments(p_post_id)`: List comments for a post with liked state
- `create_comment(p_post_id, p_text)`: Create a comment and increment posts_count
- `toggle_comment_like(p_comment_id)`: Like/unlike comment with counter update
- `list_notifications(p_user_id)`: List notifications for user
- `mark_notification_read(p_notification_id)`: Mark single notification as read
- `mark_all_notifications_read()`: Mark all notifications as read
- Trigger `trg_posts_count_increment`: Auto-increment posts_count when post created

### Applied to Production
- Migration applied via `supabase db push`
- Committed: `10e0800` → `1328cdd`
- Pushed to GitHub

## 📋 Faltando (Mobile - Luizão)

### 1. Social API Integration
- Create `lib/data/models/social_responses.dart` with response models:
  - `UserProfileResponse`
  - `UserStatsResponse`
  - `CommentResponse`
  - `NotificationResponse`

- Add methods to `lib/data/api/social_api.dart`:
  - `getUserProfile(String userId)`
  - `getUserStats(String userId)`
  - `followUser(String followerId, String followingId)`
  - `unfollowUser(String followerId, String followingId)`
  - `isFollowing(String followerId, String followingId)`
  - `listComments(String postId)`
  - `createComment(String postId, String text)`
  - `toggleCommentLike(String commentId)`
  - `listNotifications({String? userId})`
  - `markNotificationRead(String notificationId)`
  - `markAllNotificationsRead()`

### 2. Update Profile Screen
- Connect Streak Counter to `getUserStats` instead of local store
- Fetch real streakDays from backend
- Display real stats (sessions, minutes, meters, places)

### 3. Update Public Profile Screen
- Replace mock data with `getUserProfile` call
- Replace mock calendar with real data from backend
- Connect follow button to `followUser`/`unfollowUser`
- Fetch real isFollowing state

### 4. Update Comments Screen
- Connect `listComments` to real backend
- Connect `createComment` to real backend
- Connect `toggleCommentLike` to real backend
- Remove mock data

### 5. Create Notifications Screen
- Create `lib/presentation/screens/notifications/notifications_screen.dart`
- Connect to `listNotifications`
- Add swipe to mark as read
- Add "Mark all as read" button
- Connect notification bell in feed header to this screen

### 6. Update docs/contrato-rpc.md
- Add new RPCs to the contract documentation
- Update OpenAPI spec to match RPCs

## 🎯 Notes for Luizão

- All RPCs are now available in production
- Use POST to `/rest/v1/rpc/{function_name}`
- Pass parameters as JSON body with `p_` prefix
- Example:
  ```dart
  final res = await dio.post('/rest/v1/rpc/get_user_stats',
    data: {'p_user_id': userId});
  ```

- `getUserStats` returns:
  ```json
  {
    "sessions": 10,
    "minutes": 300,
    "meters": 9000,
    "places": 3,
    "streak_days": 5,
    "posts": 2
  }
  ```

- `getUserProfile` returns:
  ```json
  {
    "id": "uuid",
    "display_name": "Name",
    "avatar_url": "url",
    "bio": "Bio text",
    "followers_count": 10,
    "following_count": 5,
    "posts_count": 2
  }
  ```

## 🧪 Notes for Mat (QA)

- Test RPCs with psql or Supabase dashboard
- Verify counters update correctly
- Test follow/unfollow idempotency
- Test comment like toggle
- Verify notification read state
