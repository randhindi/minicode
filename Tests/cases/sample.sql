-- Active users per day
SELECT date_trunc('day', created_at) AS day, COUNT(*) AS n
FROM users u
JOIN sessions s ON s.user_id = u.id
WHERE u.active = TRUE AND s.duration > 30
GROUP BY 1
ORDER BY day DESC
LIMIT 10;
