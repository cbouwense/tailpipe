#import "Basic";
#import "File_Utilities";
#import "Sort";

visit_files_cb :: (info: *File_Visit_Info, user_data: *void) {
    print("% ... ", info.short_name);
    print("%\n", info.full_name);
}

main :: () {
    visit_files(".", true, null, visit_files_cb, false, true, true, true);
}