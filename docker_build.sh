cd modules && sh get-modules.sh
cd .. && docker compose build > build.log && echo "Build completed successfully."
