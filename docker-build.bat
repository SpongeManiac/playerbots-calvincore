cd modules && ./get-modules.bat
cd .. && docker compose build > build.log && echo "Build completed successfully."
