#import "Basic";
Hash :: #import "Hash";
#import "Hash_Table";
#import "File";
String :: #import "String";
using String;

add_key_value_literal :: (key_val_literal: string) #expand {
    if `has_namespace
        append(*`tailpipe_rule, "  ");

    append(*`tailpipe_rule, "  ");
    append(*`tailpipe_rule, key_val_literal);

    if `is_important
        append(*`tailpipe_rule, " !important");

    append(*`tailpipe_rule, ";\n");
}

add_key_with_parsed_value :: (key: string) #expand {
    if `has_namespace
        append(*`tailpipe_rule, "  ");

    append(*`tailpipe_rule, "  ");
    append(*`tailpipe_rule, key);
    append(*`tailpipe_rule, ":");

    for `values_and_units {
        append(*`tailpipe_rule, " ");
        append(*`tailpipe_rule, it);
    }

    if `is_important
        append(*`tailpipe_rule, " !important");

    append(*`tailpipe_rule, ";\n");
}

main :: () {
    html_file_path: string = "index.html";
    css_file_path : string = "tailpipe.css";
    verbose_mode  : bool   = false;
    watch_mode    : bool   = false;

    cli_args := get_command_line_arguments();
    for cli_args {
        if ends_with(it, ".html") {
            html_file_path = it; // TODO: can I even do this? Do I need to actually copy this or something
        }
        else if ends_with(it, ".css") {
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

    input_html := read_entire_file(html_file_path);
    
    html_rules : Table (string, Any, null, String.equal, 70, true); // using this as a Set
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

    no_namespace_rules        : Table (string, Any, null, String.equal, 70, true);
    mobile_namespace_rules    : Table (string, Any, null, String.equal, 70, true);
    tablet_namespace_rules    : Table (string, Any, null, String.equal, 70, true);
    computer_namespace_rules  : Table (string, Any, null, String.equal, 70, true);
    ultrawide_namespace_rules : Table (string, Any, null, String.equal, 70, true);
    unknown_rules             : Table (string, Any, null, String.equal, 70, true);

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

        values_and_units : [..] string;
        for 1..tokens.count-1 {
            token         := tokens[it];
            trimmed_token := trim(token, "!");
            array_add(*values_and_units, trimmed_token);
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
                    add_key_value_literal("position: absolute");
                } else if equal(abbreviated_name, "alignStart") {
                    add_key_value_literal("align-items: flex-start");
                } else if equal(abbreviated_name, "alignEnd") {
                    add_key_value_literal("align-items: flex-end");
                } else if equal(abbreviated_name, "alignCenter") {
                    add_key_value_literal("align-items: center");
                } else if equal(abbreviated_name, "alignBaseline") {
                    add_key_value_literal("align-items: baseline");
                } else if equal(abbreviated_name, "alignStretch") {
                    add_key_value_literal("align-items: stretch");
                } else if equal(abbreviated_name, "b") {
                    add_key_with_parsed_value("border");
                } else if equal(abbreviated_name, "breakAll") {
                    add_key_value_literal("word-break: break-all");
                } else if equal(abbreviated_name, "breakWord") {
                    add_key_value_literal("word-wrap: break-word");
                } else if equal(abbreviated_name, "basis") {
                    add_key_with_parsed_value("flex-basis");
                } else if equal(abbreviated_name, "bb") {
                    add_key_with_parsed_value("border-bottom");
                } else if equal(abbreviated_name, "bg") {
                    if equal(values_and_units[0], "default") {
                        add_key_value_literal("background-color: var(--background-color)");
                    } else {
                        add_key_with_parsed_value("background-color");
                    }
                } else if equal(abbreviated_name, "bl") {
                    add_key_with_parsed_value("border-left");
                } else if equal(abbreviated_name, "br") {
                    add_key_with_parsed_value("border-right");
                } else if equal(abbreviated_name, "brad") {
                    add_key_with_parsed_value("border-radius");
                } else if equal(abbreviated_name, "bt") {
                    add_key_with_parsed_value("border-top");
                } else if equal(abbreviated_name, "bottom") {
                    add_key_with_parsed_value("bottom");
                } else if equal(abbreviated_name, "bx") {
                    add_key_with_parsed_value("border-left");
                    add_key_with_parsed_value("border-right");
                } else if equal(abbreviated_name, "by") {
                    add_key_with_parsed_value("border-top");
                    add_key_with_parsed_value("border-bottom");
                } else if equal(abbreviated_name, "c") {
                    add_key_with_parsed_value("color");
                } else if equal(abbreviated_name, "column") {
                    add_key_value_literal("flex-direction: column");
                } else if equal(abbreviated_name, "dot") {
                    add_key_value_literal("list-style-type: disc");
                    add_key_value_literal("margin-left: 1.5rem");
                } else if equal(abbreviated_name, "fixed") {
                    add_key_value_literal("position: fixed");
                } else if equal(abbreviated_name, "flex") {
                    add_key_value_literal("display: flex");
                } else if equal(abbreviated_name, "fs") {
                    add_key_with_parsed_value("font-size");
                } else if equal(abbreviated_name, "gap") {
                    add_key_with_parsed_value("gap");
                } else if equal(abbreviated_name, "grid") {
                    add_key_value_literal("display: grid");
                } else if equal(abbreviated_name, "gridCol") {
                    if has_namespace append(*tailpipe_rule, "  ");

                    append(*tailpipe_rule, "  ");
                    append(*tailpipe_rule, "grid-template-columns: ");

                    if equal(values_and_units.data[0], "1") {
                        append(*tailpipe_rule, "minmax(0, 1fr)");
                    } else {
                        append(*tailpipe_rule, "repeat(");
                        append(*tailpipe_rule, values_and_units[0]);
                        append(*tailpipe_rule,", 1fr)");
                    }
                    if is_important append(*tailpipe_rule, " !important");
                    append(*tailpipe_rule, ";\n");
                } else if equal(abbreviated_name, "grow") {
                    add_key_with_parsed_value("flex-grow");
                } else if equal(abbreviated_name, "h") {
                    add_key_with_parsed_value("height");
                } else if equal(abbreviated_name, "justifyStart") {
                    add_key_value_literal("justify-content: flex-start");
                } else if equal(abbreviated_name, "justifyEnd") {
                    add_key_value_literal("justify-content: flex-end");
                } else if equal(abbreviated_name, "justifyCenter") {
                    add_key_value_literal("justify-content: center");
                } else if equal(abbreviated_name, "justifyBetween") {
                    add_key_value_literal("justify-content: space-between");
                } else if equal(abbreviated_name, "justifyAround") {
                    add_key_value_literal("justify-content: space-around");
                } else if equal(abbreviated_name, "justifyEvenly") {
                    add_key_value_literal("justify-content: space-evenly");
                } else if equal(abbreviated_name, "justifyStretch") {
                    add_key_value_literal("justify-content: stretch");
                } else if equal(abbreviated_name, "left") {
                    add_key_with_parsed_value("left");
                } else if equal(abbreviated_name, "lightShadow") {
                    add_key_value_literal("box-shadow: 0 0 16px 0 rgba(255, 255, 255, 0.2)");
                } else if equal(abbreviated_name, "lightShadowSmall") {
                    add_key_value_literal("box-shadow: 0 0 8px 0 rgba(255, 255, 255, 0.2)");
                } else if equal(abbreviated_name, "m") {
                    add_key_with_parsed_value("margin");
                } else if equal(abbreviated_name, "maxh") {
                    add_key_with_parsed_value("max-height");
                } else if equal(abbreviated_name, "maxw") {
                    add_key_with_parsed_value("max-width");
                } else if equal(abbreviated_name, "mb") {
                    add_key_with_parsed_value("margin-bottom");
                } else if equal(abbreviated_name, "minh") {
                    add_key_with_parsed_value("min-height");
                } else if equal(abbreviated_name, "minw") {
                    add_key_with_parsed_value("min-width");
                } else if equal(abbreviated_name, "ml") {
                    add_key_with_parsed_value("margin-left");
                } else if equal(abbreviated_name, "mr") {
                    add_key_with_parsed_value("margin-right");
                } else if equal(abbreviated_name, "mt") {
                    add_key_with_parsed_value("margin-top");
                } else if equal(abbreviated_name, "mx") {
                    add_key_with_parsed_value("margin-left");
                    add_key_with_parsed_value("margin-right");
                } else if equal(abbreviated_name, "my") {
                    add_key_with_parsed_value("margin-top");
                    add_key_with_parsed_value("margin-bottom");
                } else if equal(abbreviated_name, "p") {
                    add_key_with_parsed_value("padding");
                } else if equal(abbreviated_name, "pb") {
                    add_key_with_parsed_value("padding-bottom");
                } else if equal(abbreviated_name, "pl") {
                    add_key_with_parsed_value("padding-left");
                } else if equal(abbreviated_name, "pr") {
                    add_key_with_parsed_value("padding-right");
                } else if equal(abbreviated_name, "pt") {
                    add_key_with_parsed_value("padding-top");
                } else if equal(abbreviated_name, "px") {
                    add_key_with_parsed_value("padding-left");
                    add_key_with_parsed_value("padding-right");
                } else if equal(abbreviated_name, "py") {
                    add_key_with_parsed_value("padding-top");
                    add_key_with_parsed_value("padding-bottom");
                } else if equal(abbreviated_name, "right") {
                    add_key_with_parsed_value("right");
                } else if equal(abbreviated_name, "relative") {
                    add_key_value_literal("position: relative");
                } else if equal(abbreviated_name, "rounded") {
                    add_key_value_literal("border-radius: 8px;");
                } else if equal(abbreviated_name, "row") {
                    add_key_value_literal("flex-direction: row");
                } else if equal(abbreviated_name, "shadowSm") {
                    add_key_value_literal("box-shadow: 0 1px 2px 0 rgb(0, 0, 0, 0.05)");
                } else if equal(abbreviated_name, "shadow") {
                    add_key_value_literal("box-shadow: 0 1px 3px 0 rgb(0, 0, 0, 0.1), 0 1px 2px -1px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowMd") {
                    add_key_value_literal("box-shadow: 0 4px 6px -1px rgb(0, 0, 0, 0.1), 0 2px 4px -2px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowLg") {
                    add_key_value_literal("box-shadow: 0 10px 15px -3px rgb(0, 0, 0, 0.1), 0 4px 6px -4px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowXl") {
                    add_key_value_literal("box-shadow: 0 20px 25px -5px rgb(0, 0, 0, 0.1), 0 8px 10px -6px rgb(0, 0, 0, 0.1)");
                } else if equal(abbreviated_name, "shadowXxl") {
                    add_key_value_literal("box-shadow: 0 25px 50px -12px rgb(0, 0, 0, 0.25)");
                } else if equal(abbreviated_name, "shadowInner") {
                    add_key_value_literal("box-shadow: inset 0 2px 4px 0 rgb(0, 0, 0, 0.05)");
                } else if equal(abbreviated_name, "shadowNone") {
                    add_key_value_literal("box-shadow: 0 0 #0000");
                } else if equal(abbreviated_name, "shrink") {
                    add_key_with_parsed_value("flex-shrink");
                } else if equal(abbreviated_name, "sticky") {
                    add_key_value_literal("position: sticky");
                    add_key_value_literal("top: 0");
                    add_key_value_literal("box-sizing: border-box");
                } else if equal(abbreviated_name, "top") {
                    add_key_with_parsed_value("top");
                } else if equal(abbreviated_name, "underlineDots") {
                    add_key_value_literal("text-decoration: underline dotted");
                } else if equal(abbreviated_name, "w") {
                    add_key_with_parsed_value("width");
                } else if equal(abbreviated_name, "wrap") {
                    add_key_value_literal("word-wrap: break-word");
                } else if equal(abbreviated_name, "z") {
                    add_key_with_parsed_value("z-index");
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

    print("no_namespace_rules:\n");
    for no_namespace_rules {
        print("%\n", it_index);
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
    print("mobile_namespace_rules:\n");
    for mobile_namespace_rules {
        print("%\n", it_index);
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

    print("tablet_namespace_rules:\n");
    for tablet_namespace_rules {
        print("%\n", it_index);
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