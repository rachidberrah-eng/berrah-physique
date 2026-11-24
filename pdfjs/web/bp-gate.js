// berrah.app: lesson files are for logged-in students only.
(function(){try{var k='sb-exouvznkkgptvgqanawf-auth-token',v=localStorage.getItem(k),ok=false;
if(v){var o=JSON.parse(v);ok=!!(o&&(o.access_token||(o.currentSession&&o.currentSession.access_token)));}
if(!ok){location.replace('/?login=1');}}catch(e){location.replace('/?login=1');}})();
