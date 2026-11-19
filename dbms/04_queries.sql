-- V_Nue Mail - Application Queries

-- ==========================================
-- AUTH & USER PROFILE
-- ==========================================

-- READ: Get user by email for authentication
SELECT id, email, password_hash, display_name 
FROM users 
WHERE email = 'test@vnuemail.local';

-- WRITE: Register a new user
INSERT INTO users (email, password_hash, display_name) 
VALUES ('new@vnuemail.local', '$2a$10$...', 'New User')
RETURNING id;

-- READ: Get user profile with settings (JOIN)
SELECT u.id, u.email, u.display_name, s.theme, s.density, s.signature, s.keyboard_shortcuts
FROM users u
LEFT JOIN user_settings s ON u.id = s.user_id
WHERE u.email = 'test@vnuemail.local';

-- WRITE: Initialize user settings
INSERT INTO user_settings (user_id, theme, density)
VALUES ('00000000-0000-0000-0000-000000000000', 'dark', 'comfortable')
ON CONFLICT (user_id) DO NOTHING;

-- WRITE: Update user settings
UPDATE user_settings 
SET theme = 'light', density = 'compact', updated_at = NOW()
WHERE user_id = '00000000-0000-0000-0000-000000000000';


-- ==========================================
-- MAILBOX VIEW QUERIES (READ)
-- ==========================================

-- READ: Get Inbox (Messages where user is a recipient, not trashed, not deleted, not draft)
SELECT m.*, u.display_name as sender_name
FROM messages m
LEFT JOIN users u ON m.sender = u.email
WHERE 'test@vnuemail.local' = ANY(m.recipient)
  AND m.recipient_trash = FALSE 
  AND m.recipient_deleted = FALSE 
  AND m.is_draft = FALSE
  AND m.recipient_spam = FALSE
ORDER BY m.created_at DESC;

-- READ: Get Sent folder
SELECT m.*
FROM messages m
WHERE m.sender = 'test@vnuemail.local'
  AND m.sender_trash = FALSE 
  AND m.sender_deleted = FALSE 
  AND m.is_draft = FALSE
ORDER BY m.created_at DESC;

-- READ: Get Drafts
SELECT * FROM messages 
WHERE sender = 'test@vnuemail.local' 
  AND is_draft = TRUE 
  AND sender_deleted = FALSE
ORDER BY created_at DESC;

-- READ: Get Starred (Messages starred by user as either sender or recipient)
SELECT * FROM messages 
WHERE (
    (sender = 'test@vnuemail.local' AND sender_starred = TRUE AND sender_trash = FALSE)
    OR 
    ('test@vnuemail.local' = ANY(recipient) AND recipient_starred = TRUE AND recipient_trash = FALSE)
)
AND recipient_deleted = FALSE AND sender_deleted = FALSE
ORDER BY created_at DESC;

-- READ: Get Trash
SELECT * FROM messages 
WHERE (
    (sender = 'test@vnuemail.local' AND sender_trash = TRUE AND sender_deleted = FALSE)
    OR 
    ('test@vnuemail.local' = ANY(recipient) AND recipient_trash = TRUE AND recipient_deleted = FALSE)
)
ORDER BY created_at DESC;

-- READ: Get Thread/Single Message Detail
SELECT m.*, u.display_name as sender_display_name
FROM messages m
LEFT JOIN users u ON m.sender = u.email
WHERE m.id = '00000000-0000-0000-0000-000000000000';


-- ==========================================
-- MESSAGE ACTIONS (WRITE)
-- ==========================================

-- WRITE: Send a new message
INSERT INTO messages (sender, recipient, subject, body, body_html, cc, bcc, attachments)
VALUES ('test@vnuemail.local', ARRAY['friend@vnuemail.local'], 'Hello', 'Body content', '<p>Body content</p>', '', '', '[]'::jsonb);

-- WRITE: Save a draft
INSERT INTO messages (sender, recipient, subject, body, is_draft)
VALUES ('test@vnuemail.local', ARRAY['someone@else.com'], 'Draft Subject', 'Work in progress...', TRUE);

-- WRITE: Update draft and mark as sent
UPDATE messages 
SET recipient = ARRAY['friend@vnuemail.local'], 
    subject = 'Updated Subject', 
    body = 'Final content', 
    is_draft = FALSE, 
    created_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000000' AND sender = 'test@vnuemail.local';

-- WRITE: Mark as Read/Unread (as recipient)
UPDATE messages 
SET status = 'read' 
WHERE id = '00000000-0000-0000-0000-000000000000' AND 'test@vnuemail.local' = ANY(recipient);

-- WRITE: Toggle Star (as recipient)
UPDATE messages 
SET recipient_starred = NOT recipient_starred 
WHERE id = '00000000-0000-0000-0000-000000000000' AND 'test@vnuemail.local' = ANY(recipient);

-- WRITE: Move to Trash (as recipient)
UPDATE messages 
SET recipient_trash = TRUE 
WHERE id = '00000000-0000-0000-0000-000000000000' AND 'test@vnuemail.local' = ANY(recipient);

-- WRITE: Permanent Delete (Soft delete flag)
UPDATE messages 
SET recipient_deleted = TRUE 
WHERE id = '00000000-0000-0000-0000-000000000000' AND 'test@vnuemail.local' = ANY(recipient);


-- ==========================================
-- LABELS & CATEGORIES
-- ==========================================

-- READ: Get all custom labels for a user
SELECT * FROM custom_labels 
WHERE user_id = (SELECT id FROM users WHERE email = 'test@vnuemail.local');

-- WRITE: Create new custom label
INSERT INTO custom_labels (user_id, name, color)
VALUES ('00000000-0000-0000-0000-000000000000', 'Work', '#FF5733');

-- WRITE: Apply label to message
UPDATE messages 
SET labels = array_append(labels, 'Work')
WHERE id = '00000000-0000-0000-0000-000000000000' 
  AND ('test@vnuemail.local' = ANY(recipient) OR sender = 'test@vnuemail.local')
  AND NOT ('Work' = ANY(labels));

-- READ: Get messages by label
SELECT * FROM messages 
WHERE 'Work' = ANY(labels) 
  AND ('test@vnuemail.local' = ANY(recipient) OR sender = 'test@vnuemail.local')
ORDER BY created_at DESC;
