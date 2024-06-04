@attached(accessor)
public macro scriptValue() = #externalMacro(module: "WyrmMacros", type: "ScriptValueMacro")

@attached(accessor)
public macro scriptValue<T>(default value: T) = #externalMacro(module: "WyrmMacros", type: "ScriptValueMacro")
