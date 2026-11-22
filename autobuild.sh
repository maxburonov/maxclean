#!/bin/zsh
# Max Clean — avtomatik build kuzatuvchisi.
# Bir marta ishga tushiring: ./autobuild.sh   (to'xtatish: Ctrl+C)
# .rebuild fayli o'zgarganda ./build.sh ni qayta ishga tushiradi va natijani build.log / build.status ga yozadi.
cd "$(dirname "$0")"
touch .rebuild
last=""
echo "👀 Kuzatuv boshlandi (Ctrl+C — to'xtatish)…"
while true; do
  cur=$(stat -f %m .rebuild 2>/dev/null)
  if [[ "$cur" != "$last" ]]; then
    last="$cur"
    echo "running" > build.status
    echo "▶ Build boshlandi: $(date '+%H:%M:%S')"
    VER=$(cat .version 2>/dev/null)
    if zsh ./build.sh $VER > build.log 2>&1; then
      echo "ok" > build.status; echo "✅ Muvaffaqiyatli"
    else
      echo "fail" > build.status; echo "❌ Xato — Claude tuzatyapti…"
    fi
  fi
  sleep 2
done
