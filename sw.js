// Service Worker بسيط — الشرط الأساسي لتحويل الموقع لتطبيق (PWA)
// لا يقوم بتخزين مؤقت ثقيل، فقط يجعل المتصفح يعتبر الموقع "قابلاً للتنصيب"

const CACHE_NAME = 'berrah-physics-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// استراتيجية بسيطة: جرب الشبكة أولاً، وإذا فشلت (بلا انترنت) استعمل النسخة المخزنة إن وجدت
self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
