#if TEAM && PROJECT
    print("Hello from a Pkl-generated Xcode project!")
#else
    #error("Expected both imported target settings and inherited project settings")
#endif
