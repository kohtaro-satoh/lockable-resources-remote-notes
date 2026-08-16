# Union coverage — how to regenerate

`site/` is the browsable report; `exec/` is what it was built from, minus the unit layer: that one
is 16 MB and comes straight back out of `mvn -P enable-jacoco verify`. The HTML for the other two
layers was dropped because it regenerates from their `exec/` plus the plugin built at the same
commit, and 160 files of it per layer is a lot of noise to carry for something derivable:

    cd <plugin> && git checkout bdca858 && mvn -DskipTests package
    cd <harness>/dev/jenkins-env
    ./coverage/union.sh --unit <plugin>/target/jacoco.exec \
                        --exec ../reports/<id>-coverage-e2e/exec \
                        --exec ../reports/<id>-coverage-load-stress/exec

The class ids in an exec file are hashes of the bytecode, so the report only matches against the
commit it was measured on. Rebuild a different commit and JaCoCo silently reports those classes as
uncovered — which is exactly the failure this directory exists to help investigate.
