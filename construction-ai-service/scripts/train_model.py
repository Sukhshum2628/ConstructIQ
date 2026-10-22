import pandas as pd
import numpy as np
from xgboost import XGBClassifier
from sklearn.model_selection import train_test_split, cross_val_score, StratifiedKFold
from sklearn.metrics import (classification_report, confusion_matrix,
                              roc_auc_score, accuracy_score)
import joblib
import os
import mlflow
import mlflow.xgboost

mlflow.set_experiment("constructiq-cost-overrun")

def train_and_log_model(X_train, y_train, X_test, y_test, params):
    with mlflow.start_run():
        model = XGBClassifier(**params)
        model.fit(X_train, y_train)
        
        y_prob = model.predict_proba(X_test)[:, 1]
        y_pred = model.predict(X_test)
        auc = roc_auc_score(y_test, y_prob)
        acc = accuracy_score(y_test, y_pred)
        
        mlflow.log_params(params)
        mlflow.log_metric("auc", auc)
        mlflow.log_metric("accuracy", acc)
        mlflow.log_metric("train_samples", len(X_train))
        mlflow.log_metric("test_samples", len(X_test))
        mlflow.xgboost.log_model(model, "cost-overrun-classifier")
        
        return model, auc, acc, y_pred

def train_model():
    if not os.path.exists("data/training_data.csv"):
        print("Dataset not found. Run generate_dataset.py first.")
        return

    # Load data
    df = pd.read_csv("data/training_data.csv")
    X = df.drop("overrun_binary", axis=1)
    y = df["overrun_binary"]

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Model with regularisation to prevent overfitting
    params = {
        "n_estimators": 100,
        "max_depth": 4,
        "learning_rate": 0.1,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "reg_alpha": 0.1,
        "reg_lambda": 1.0,
        "eval_metric": "logloss",
        "random_state": 42
    }
    
    print("Training model and logging to MLflow...")
    model, auc, acc, y_pred = train_and_log_model(X_train, y_train, X_test, y_test, params)

    print("=" * 50)
    print(f"Test AUC-ROC:  {auc:.4f}")
    print(f"Test Accuracy: {acc:.4f}")
    print()
    print("Classification Report:")
    print(classification_report(y_test, y_pred, target_names=["No Overrun", "Overrun"]))
    print("Confusion Matrix:")
    print(confusion_matrix(y_test, y_pred))

    # 5-fold cross validation for robustness check
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    cv_aucs = cross_val_score(model, X, y, cv=cv, scoring="roc_auc")
    print(f"\n5-Fold CV AUC: {cv_aucs.mean():.4f} (+/- {cv_aucs.std():.4f})")
    print("=" * 50)

    # Feature importance
    importance = dict(zip(X.columns, model.feature_importances_))
    # Filter out internal fields if any
    print("\nFeature Importances:")
    for feat, imp in sorted(importance.items(), key=lambda x: -x[1]):
        print(f"  {feat}: {imp:.4f}")

    # Save model
    os.makedirs("models", exist_ok=True)
    joblib.dump(model, "models/cost_overrun_model.pkl")
    print("\nModel saved to models/cost_overrun_model.pkl")

if __name__ == "__main__":
    train_model()

