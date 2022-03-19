FROM nextstrain/base:latest

WORKDIR /covid-19-puerto-rico-nextstrain

# Essential upstream content
COPY LICENSE Snakefile ./
COPY defaults/ defaults/
COPY scripts/ scripts/
COPY workflow/ workflow/
COPY nextstrain_profiles/ nextstrain_profiles/

# Non-essential upstream content, useful for testing
COPY my_profiles/ my_profiles/
COPY tests/ tests/
COPY data/ data/
COPY narratives/ narratives/
COPY docs/ docs/

# Our repo's actual original content
COPY docker-entrypoint.sh ./
COPY puerto-rico_profiles/ puerto-rico_profiles/

ENTRYPOINT ["./docker-entrypoint.sh"]