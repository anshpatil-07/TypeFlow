import os
import json

def setup():
    print("=== TypeFlow Normal Launch Configuration Setup ===")
    
    home = os.path.expanduser("~")
    app_support = os.path.join(home, "Library", "Application Support", "TypeFlow")
    
    os.makedirs(app_support, exist_ok=True)
    
    config_path = os.path.join(app_support, "model-config.json")
    
    print("We will configure TypeFlow for normal launch (without CLI args).")
    model_path = input("Enter the absolute path to your Qwen FIM model (e.g., /Users/name/.../Qwen2.5-Coder-1.5B.Q4_K_M.gguf):\n> ").strip()
    
    if not model_path:
        print("Model path cannot be empty.")
        return
        
    if not os.path.exists(model_path):
        print(f"Warning: The file '{model_path}' does not exist right now, but we will save the config anyway.")
    
    config = {
        "modelPath": model_path,
        "modelProfileID": "qwenCoderFIM"
    }
    
    with open(config_path, "w") as f:
        json.dump(config, f, indent=4)
        
    print(f"\nConfiguration saved successfully to:\n{config_path}")
    print("\nYou can now launch TypeFlow normally and it will use this model configuration.")

if __name__ == "__main__":
    setup()
