cd modules && sh get-modules.sh
cd .. && docker compose build --progress plain 2>&1 | tee build.log && echo "Build completed successfully."
