#import "Basic";
Hash :: #import "Hash";
#import "Hash_Table";
#import "File";
#import "File_Utilities";
File_Watcher :: #import "File_Watcher";
String :: #import "String";
using String;

ADD_KEY_VALUE_LITERAL :: (key_val_literal: string) #expand {
    if `has_namespace
        append(*`tailpipe_rule, "  ");

    append(*`tailpipe_rule, "  ");
    append(*`tailpipe_rule, key_val_literal);

    if `is_important
        append(*`tailpipe_rule, " !important");

    append(*`tailpipe_rule, ";\n");
}

ADD_KEY_WITH_PARSED_VALUE :: (key: string) -> bool #expand {
    if `value_and_unit.count == 0 {
        if `verbose_mode
            print("WARNING: Unable to parse value and unit for `%`. It could be that the html intended to use tailpipe class names but forgot their values (for example, class=\"b-\"). It's also possible that the html simply isn't using tailpipe, and happened to use the same class names as tailpipe names. Or a mixture of both. In any case, we can't add this rule to the output stylesheet (%).\n", `abbreviated_name, `css_file_path);

        if !table_contains(*`unknown_rules, `html_rule) {
            table_add(*`unknown_rules, `html_rule, 0);
        }

        continue; // Do not add this to the resulting stylesheet.
    }
    
    if `has_namespace
        append(*`tailpipe_rule, "  ");

    append(*`tailpipe_rule, "  ");
    append(*`tailpipe_rule, key);
    append(*`tailpipe_rule, ":");

    for `value_and_unit {
        append(*`tailpipe_rule, " ");
        append(*`tailpipe_rule, it);
    }

    if `is_important
        append(*`tailpipe_rule, " !important");

    append(*`tailpipe_rule, ";\n");

    return true;
}

css_file_path : string = "tailpipe.css";
verbose_mode  : bool   = false;
watch_mode    : bool   = false;

file_change_callback :: (watcher: *File_Watcher.File_Watcher(void), change: *File_Watcher.File_Change, user_data: *void) {
    file_path_string := change.full_path;
    file_path := parse_path(file_path_string);
    file_name := file_path.words[file_path.words.count - 1];
    print("detected change to %\n", file_name);

    if ends_with(change.full_path, ".html") {
        if verbose_mode {
            print("Detected change to %, regenerating %", file_path_string, css_file_path);
        }
        run(file_path_string);
    }
}

run :: (html_file_path: string) {
    input_html := read_entire_file(html_file_path);
    
    // Using these all as Sets.
    // TODO: make a Set in Jai
    html_rules                : Table (string, Any, null, String.equal, 70, true);
    no_namespace_rules        : Table (string, Any, null, String.equal, 70, true);
    mobile_namespace_rules    : Table (string, Any, null, String.equal, 70, true);
    tablet_namespace_rules    : Table (string, Any, null, String.equal, 70, true);
    computer_namespace_rules  : Table (string, Any, null, String.equal, 70, true);
    ultrawide_namespace_rules : Table (string, Any, null, String.equal, 70, true);
    unknown_rules             : Table (string, Any, null, String.equal, 70, true);

    // Pass a rolling view of 7 characters over the entire html file. If we find class=" then we
    // save all of the characters until the next ", split them apart by spaces, and throw them
    // all into the Set called html_rules. These html_rules are then processed in the next section
    // into tailpipe rules.
    {
        i: int = 0;
        while i < input_html.count - 7 {
            defer i += 1;

            view := slice(input_html, i, 7);
            
            if !equal(view, "class=\"") continue;

            i += 7;
            j := i;
            while input_html[j] != #char "\"" {
                j += 1;
            }

            view = trim(slice(input_html, i, j - i));

            tokens := split(view, " ");
            for tokens {
                if !table_contains(*html_rules, it)
                    table_add(*html_rules, it, 0); // 0 is just a throwaway value, since Sets don't need values.
            }            
        }
    }

    for html_rules {
        // "m:fs-1rem!"
        html_rule := it_index;

        // "m:fs-1rem" -> ["m:fs", "1rem!"]
        tokens := split(html_rule, "-");
        // "m:fs" -> ["m", "fs"]
        name_and_namespace_as_tokens := split(tokens[0], ":");

        // A "namespace" is a prefix for specifying the device type (e.g. `m:` for mobile, `uw:` for ultra-wide).
        has_namespace    := name_and_namespace_as_tokens.count == 2;
        abbreviated_name := ifx has_namespace
            then name_and_namespace_as_tokens.data[1]
            else name_and_namespace_as_tokens.data[0];

        value_and_unit : [..] string;
        for 1..tokens.count-1 {
            token         := tokens[it];
            trimmed_token := trim(token, "!");
            array_add(*value_and_unit, trimmed_token);
        }

        is_important    := false;
        tailpipe_class : String_Builder;
        tailpipe_rule  : String_Builder;
        init_string_builder(*tailpipe_class);

        // Construct the CSS rule that will be inserted into the stylesheet file.
        {
            // Construct the class name for the rule. Delimit special characters, since CSS3 can't handle them unless they're delimited.
            for html_rule {
                if it == {
                    case #char ":";
                        append(*tailpipe_class, "\\:");
                    case #char "!";
                        append(*tailpipe_class, "\\!");
                        is_important = true;
                    case #char "%";
                        append(*tailpipe_class, "\\%");
                    case #char ".";
                        append(*tailpipe_class, "\\.");
                    case #char "#";
                        append(*tailpipe_class, "\\#");
                    case; // default
                        append(*tailpipe_class, it);
                }
            }

            // These keywords are used by the media queries and don't need anything to be auto generated for them.
            if equal(html_rule, "mobile")    continue;
            if equal(html_rule, "tablet")    continue;
            if equal(html_rule, "computer")  continue;
            if equal(html_rule, "ultrawide") continue;

            // Add classname
            if has_namespace append(*tailpipe_rule, "  "); // Indent once if inside of a media query.
            append(*tailpipe_rule, ".");
            append_and_steal_buffers(*tailpipe_rule, *tailpipe_class); // TODO: I wonder if this is a terrible idea.
            append(*tailpipe_rule, " {\n");

            // Add properties
            {
                if equal(abbreviated_name, "absolute") {
                    ADD_KEY_VALUE_LITERAL("position: absolute");
                } else if equal(abbreviated_name, "alignStart") {
                    ADD_KEY_VALUE_LITERAL("align-items: flex-start");
                } else if equal(abbreviated_name, "alignEnd") {
                    ADD_KEY_VALUE_LITERAL("align-items: flex-end");
                } else if equal(abbreviated_name, "alignCenter") {
                    ADD_KEY_VALUE_LITERAL("align-items: center");
                } else if equal(abbreviated_name, "alignBaseline") {
                    ADD_KEY_VALUE_LITERAL("align-items: baseline");
                } else if equal(abbreviated_name, "alignStretch") {
                    ADD_KEY_VALUE_LITERAL("align-items: stretch");
                } else if equal(abbreviated_name, "b") {
                    ADD_KEY_WITH_PARSED_VALUE("border");
                } else if equal(abbreviated_name, "breakAll") {
                    ADD_KEY_VALUE_LITERAL("word-break: break-all");
                } else if equal(abbreviated_name, "breakWord") {
                    ADD_KEY_VALUE_LITERAL("word-wrap: break-word");
                } else if equal(abbreviated_name, "basis") {
                    ADD_KEY_WITH_PARSED_VALUE("flex-basis");
                } else if equal(abbreviated_name, "bb") {
                    ADD_KEY_WITH_PARSED_VALUE("border-bottom");
                } else if equal(abbreviated_name, "bg") {
                    if equal(value_and_unit[0], "default") {
                        ADD_KEY_VALUE_LITERAL("background-color: var(--background-color)");
                    } else {
                        ADD_KEY_WITH_PARSED_VALUE("background-color");
                    }
                } else if equal(abbreviated_name, "bl") {
                    ADD_KEY_WITH_PARSED_VALUE("border-left");
                } else if equal(abbreviated_name, "br") {
                    ADD_KEY_WITH_PARSED_VALUE("border-right");
                } else if equal(abbreviated_name, "brad") {
                    ADD_KEY_WITH_PARSED_VALUE("border-radius");
                } else if equal(abbreviated_name, "bt") {
                    ADD_KEY_WITH_PARSED_VALUE("border-top");
                } else if equal(abbreviated_name, "bottom") {
                    ADD_KEY_WITH_PARSED_VALUE("bottom");
                } else if equal(abbreviated_name, "bx") {
                    ADD_KEY_WITH_PARSED_VALUE("border-left");
                    ADD_KEY_WITH_PARSED_VALUE("border-right");
                } else if equal(abbreviated_name, "by") {
                    ADD_KEY_WITH_PARSED_VALUE("border-top");
                    ADD_KEY_WITH_PARSED_VALUE("border-bottom");
                } else if equal(abbreviated_name, "c") {
                    ADD_KEY_WITH_PARSED_VALUE("color");
                } else if equal(abbreviated_name, "column") {
                    ADD_KEY_VALUE_LITERAL("flex-direction: column");
                } else if equal(abbreviated_name, "dot") {
                    ADD_KEY_VALUE_LITERAL("list-style-type: disc");
                    ADD_KEY_VALUE_LITERAL("margin-left: 1.5rem");
                } else if equal(abbreviated_name, "fixed") {
                    ADD_KEY_VALUE_LITERAL("position: fixed");
                } else if equal(abbreviated_name, "flex") {
                    ADD_KEY_VALUE_LITERAL("display: flex");
                } else if equal(abbreviated_name, "fs") {
                    ADD_KEY_WITH_PARSED_VALUE("font-size");
                } else if equal(abbreviated_name, "gap") {
                    ADD_KEY_WITH_PARSED_VALUE("gap");
                } else if equal(abbreviated_name, "grid") {
                    ADD_KEY_VALUE_LITERAL("display: grid");
                } else if equal(abbreviated_name, "gridCol") {
                    if has_namespace append(*tailpipe_rule, "  ");

                    append(*tailpipe_rule, "  ");
                    append(*tailpipe_rule, "grid-template-columns: ");

                    if equal(value_and_unit.data[0], "1") {
                        append(*tailpipe_rule, "minmax(0, 1fr)");
                    } else {
                        append(*tailpipe_rule, "repeat(");
                        append(*tailpipe_rule, value_and_unit[0]);
                        append(*tailpipe_rule,", 1fr)");
                    }
                    if is_important append(*tailpipe_rule, " !important");
                    append(*tailpipe_rule, ";\n");
                } else if equal(abbreviated_name, "grow") {
                    ADD_KEY_WITH_PARSED_VALUE("flex-grow");
                } else if equal(abbreviated_name, "h") {
                    ADD_KEY_WITH_PARSED_VALUE("height");
                } else if equal(abbreviated_name, "justifyStart") {
                    ADD_KEY_VALUE_LITERAL("justify-content: flex-start");
                } else if equal(abbreviated_name, "justifyEnd") {
                    ADD_KEY_VALUE_LITERAL("justify-content: flex-end");
                } else if equal(abbreviated_name, "justifyCenter") {
                    ADD_KEY_VALUE_LITERAL("justify-content: center");
                } else if equal(abbreviated_name, "justifyBetween") {
                    ADD_KEY_VALUE_LITERAL("justify-content: space-between");
                } else if equal(abbreviated_name, "justifyAround") {
                    ADD_KEY_VALUE_LITERAL("justify-content: space-around");
                } else if equal(abbreviated_name, "justifyEvenly") {
                    ADD_KEY_VALUE_LITERAL("justify-content: space-evenly");
                } else if equal(abbreviated_name, "justifyStretch") {
                    ADD_KEY_VALUE_LITERAL("justify-content: stretch");
                } else if equal(abbreviated_name, "left") {
                    ADD_KEY_WITH_PARSED_VALUE("left");
                } else if equal(abbreviated_name, "lightShadow") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 0 16px 0 rgba(255, 255, 255, 0.2)");
                } else if equal(abbreviated_name, "lightShadowSmall") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 0 8px 0 rgba(255, 255, 255, 0.2)");
                } else if equal(abbreviated_name, "m") {
                    ADD_KEY_WITH_PARSED_VALUE("margin");
                } else if equal(abbreviated_name, "maxh") {
                    ADD_KEY_WITH_PARSED_VALUE("max-height");
                } else if equal(abbreviated_name, "maxw") {
                    ADD_KEY_WITH_PARSED_VALUE("max-width");
                } else if equal(abbreviated_name, "mb") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-bottom");
                } else if equal(abbreviated_name, "minh") {
                    ADD_KEY_WITH_PARSED_VALUE("min-height");
                } else if equal(abbreviated_name, "minw") {
                    ADD_KEY_WITH_PARSED_VALUE("min-width");
                } else if equal(abbreviated_name, "ml") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-left");
                } else if equal(abbreviated_name, "mr") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-right");
                } else if equal(abbreviated_name, "mt") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-top");
                } else if equal(abbreviated_name, "mx") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-left");
                    ADD_KEY_WITH_PARSED_VALUE("margin-right");
                } else if equal(abbreviated_name, "my") {
                    ADD_KEY_WITH_PARSED_VALUE("margin-top");
                    ADD_KEY_WITH_PARSED_VALUE("margin-bottom");
                } else if equal(abbreviated_name, "p") {
                    ADD_KEY_WITH_PARSED_VALUE("padding");
                } else if equal(abbreviated_name, "pb") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-bottom");
                } else if equal(abbreviated_name, "pl") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-left");
                } else if equal(abbreviated_name, "pr") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-right");
                } else if equal(abbreviated_name, "pt") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-top");
                } else if equal(abbreviated_name, "px") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-left");
                    ADD_KEY_WITH_PARSED_VALUE("padding-right");
                } else if equal(abbreviated_name, "py") {
                    ADD_KEY_WITH_PARSED_VALUE("padding-top");
                    ADD_KEY_WITH_PARSED_VALUE("padding-bottom");
                } else if equal(abbreviated_name, "right") {
                    ADD_KEY_WITH_PARSED_VALUE("right");
                } else if equal(abbreviated_name, "relative") {
                    ADD_KEY_VALUE_LITERAL("position: relative");
                } else if equal(abbreviated_name, "rounded") {
                    ADD_KEY_VALUE_LITERAL("border-radius: 8px");
                } else if equal(abbreviated_name, "row") {
                    ADD_KEY_VALUE_LITERAL("flex-direction: row");
                } else if equal(abbreviated_name, "shadowSm") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 1px 2px 0 rgb(0, 0, 0, 0.05)");
                } else if equal(abbreviated_name, "shadow") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 1px 3px 0 rgb(0, 0, 0, 0.1), 0 1px 2px -1px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowMd") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 4px 6px -1px rgb(0, 0, 0, 0.1), 0 2px 4px -2px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowLg") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 10px 15px -3px rgb(0, 0, 0, 0.1), 0 4px 6px -4px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowXl") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 20px 25px -5px rgb(0, 0, 0, 0.1), 0 8px 10px -6px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowXxl") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 25px 50px -12px rgb(0, 0, 0, 0.25)");
                } else if equal(abbreviated_name, "shadowInner") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: inset 0 2px 4px 0 rgb(0, 0, 0, 0.05)");
                } else if equal(abbreviated_name, "shadowNone") {
                    ADD_KEY_VALUE_LITERAL("box-shadow: 0 0 #0000");
                } else if equal(abbreviated_name, "shrink") {
                    ADD_KEY_WITH_PARSED_VALUE("flex-shrink");
                } else if equal(abbreviated_name, "sticky") {
                    ADD_KEY_VALUE_LITERAL("position: sticky");
                    ADD_KEY_VALUE_LITERAL("top: 0");
                    ADD_KEY_VALUE_LITERAL("box-sizing: border-box");
                } else if equal(abbreviated_name, "top") {
                    ADD_KEY_WITH_PARSED_VALUE("top");
                } else if equal(abbreviated_name, "underlineDots") {
                    ADD_KEY_VALUE_LITERAL("text-decoration: underline dotted");
                } else if equal(abbreviated_name, "w") {
                    ADD_KEY_WITH_PARSED_VALUE("width");
                } else if equal(abbreviated_name, "wrap") {
                    ADD_KEY_VALUE_LITERAL("word-wrap: break-word");
                } else if equal(abbreviated_name, "z") {
                    if value_and_unit.count
                    ADD_KEY_WITH_PARSED_VALUE("z-index");
                } else { // Parsed an unsupported token
                    if !table_contains(*unknown_rules, html_rule) {
                        table_add(*unknown_rules, html_rule, 0);
                    }

                    // If this rule is not supported by tailpipe, then we don't actually want to add it to the
                    // generated tailpipe rule, so just continue here to move onto the next rule.
                    continue;
                }
            }

            if has_namespace append(*tailpipe_rule, "  ");
            append(*tailpipe_rule, "}");
        }

        tailpipe_rule_string: string = builder_to_string(*tailpipe_rule);

        if starts_with(html_rule, "m:") {
            table_add(*mobile_namespace_rules, tailpipe_rule_string, 0);
        } else if starts_with(html_rule, "t:") {
            table_add(*tablet_namespace_rules, tailpipe_rule_string, 0);
        } else if starts_with(html_rule, "c:") {
            table_add(*computer_namespace_rules, tailpipe_rule_string, 0);
        } else if starts_with(html_rule, "uw:") {
            table_add(*ultrawide_namespace_rules, tailpipe_rule_string, 0);
        } else {
            table_add(*no_namespace_rules, tailpipe_rule_string, 0);
        }
    }

    if (unknown_rules.count > 0 && verbose_mode) {
        print("WARNING: Tailpipe found the following class names but didn't recognize them. These are probably just custom classes you have, but you might want to check out this list just in case:\n");
        for unknown_rules {
            print("%\n", it_index);
        }
    }
    if (verbose_mode) {
        print("Successfully generated tailpipe rules.\n");
    }

    // Write the lines to the final css file
    if (verbose_mode) {
        print("Writing tailpipe rules to %...\n", css_file_path);
    }

    final_output: String_Builder;
    append(*final_output, "/**\n * Stylesheet generated by tailpipe https://github.com/cbouwense/tailpipe.\n");
    append(*final_output, " * You can edit this file, but I would not recommend it since it will be overwritten without warning the next time you run tailpipe.\n");
    append(*final_output, " * If you want to add your own rules, I recommend you add them to a separate stylesheets (I use a 'custom.css' file for this).\n */\n");

    for no_namespace_rules {
        append(*final_output, it_index);
        append(*final_output, "\n");
    }
    append(*final_output, "\n\n");

    append(*final_output, "/* Mobile */\n");
    append(*final_output, "@media (max-width: 768px) {\n");
    append(*final_output, "  .mobile { display: inherit; }\n");
    append(*final_output, "  .tablet { display: none; }\n");
    append(*final_output, "  .computer { display: none; }\n");
    append(*final_output, "  .ultrawide { display: none; }\n");
    append(*final_output, "  :root { font-size: 14px; }\n");
    for mobile_namespace_rules {
        append(*final_output, it_index);
        append(*final_output, "\n");
    }
    append(*final_output, "}\n\n");

    append(*final_output, "/* Tablet */\n");
    append(*final_output, "@media (min-width: 768px) and (max-width: 1024px) {\n");
    append(*final_output, "  .mobile { display: none; }\n");
    append(*final_output, "  .tablet { display: inherit; }\n");
    append(*final_output, "  .computer { display: none; }\n");
    append(*final_output, "  .ultrawide { display: none; }\n");
    append(*final_output, "  :root { font-size: 14px; }\n");
    for tablet_namespace_rules {
        append(*final_output, it_index);
        append(*final_output, "\n");
    }
    append(*final_output, "}\n\n");

    append(*final_output, "/* Computer (desktop / laptop) */\n");
    append(*final_output, "@media (min-width: 1024px) and (max-width: 3840px) {\n");
    append(*final_output, "  .mobile { display: none; }\n");
    append(*final_output, "  .tablet { display: none; }\n");
    append(*final_output, "  .computer { display: inherit; }\n");
    append(*final_output, "  .ultrawide { display: none; }\n");
    append(*final_output, "  :root { font-size: 18px; }\n");
    for computer_namespace_rules {
        append(*final_output, it_index);
        append(*final_output, "\n");
    }
    append(*final_output, "}\n\n");

    append(*final_output, "/* Ultrawide */\n");
    append(*final_output, "@media (min-width: 3840px) {\n");
    append(*final_output, "  .mobile { display: none; }\n");
    append(*final_output, "  .tablet { display: none; }\n");
    append(*final_output, "  .computer { display: none; }\n");
    append(*final_output, "  .ultrawide { display: inherit; }\n");
    append(*final_output, "  :root { font-size: 18px; }\n");
    for ultrawide_namespace_rules {
        append(*final_output, it_index);
        append(*final_output, "\n");
    }
    append(*final_output, "}\n\n");

    write_succeeded := write_entire_file(css_file_path, *final_output);

    if !write_succeeded {
        print("ERROR: Unable to write to %\n", css_file_path);
        exit(1);
    }

    if verbose_mode {
        print("Successfully wrote tailpipe rules to %.\n", css_file_path);
        print("All done, hope it looks good!\n");
    }
}

main :: () {
    { // Process arguments
        cli_args := get_command_line_arguments();
        for cli_args {
            // if ends_with(it, ".html") {
            //     html_file_path = it;
            // }
            // else if ends_with(it, ".css") {
            if ends_with(it, ".css") {
                css_file_path = it;
            }
            // Help text
            else if equal(it, "-h") || equal(it, "--help") {
                print("Usage: % [optional input.html] [optional output.css] [flags]\n", cli_args[0]);
                print("Flags:\n");
                print("  -h, --help     Display this help message\n");
                print("  -v, --verbose  Enable verbose output\n");
                print("  -w, --watch    Enable watch mode, so tailpipe runs on every input html modification\n");
                exit(0);
            }
            else if equal(it, "-v") || equal(it, "--verbose") {
                verbose_mode = true;
            }
            else if equal(it, "-w") || equal(it, "--watch") {
                watch_mode = true;
            }
        }
    }

    // Check to see if the html file even exists.
    // if !file_exists(html_file_path) {
    //     if verbose_mode {
    //         print("ERROR: unable to find input html file at \"%\". Are you sure the pathing is correct?", html_file_path);
    //         cwd := get_working_directory();
    //         print("Current working directory: %\n", cwd);
    //     }
    //     exit(1);
    // }

    if watch_mode {
        directories: [..] string;
        array_add(*directories, ".");
        
        visit_files_cb :: (info: *File_Visit_Info, user_data: [..]string) {
            // print("%\n", info.full_name);
            array_add(*user_data, info.full_name);
        }
        visit_files(".", true, directories, visit_files_cb, false, true, true, true);

        watcher: File_Watcher.File_Watcher(); // TODO: pass in the info instead of having globals
        watcher_init_succeeded := File_Watcher.init(*watcher, file_change_callback, events_to_watch = .MODIFIED, 0.1);
        if !watcher_init_succeeded {
            log_error("Could not initialize watcher");
            exit(1);
        }
        defer File_Watcher.deinit(watcher);

        add_directories_succeeded := File_Watcher.add_directories(*watcher, ..directories);
        if !add_directories_succeeded {
            log_error("Could not add directory to watcher");
            exit(1);
        }

        while true {
            changed, needs_wait, wait_seconds := File_Watcher.process_changes(*watcher);
            reset_temporary_storage();
            sleep_milliseconds(100);
        }

    } else {
        // TODO
        run("index.html");
    }
}