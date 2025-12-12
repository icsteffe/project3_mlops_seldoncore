import argparse
import wandb
import lightning as L
from lightning.pytorch.loggers import WandbLogger
from lightning.pytorch.callbacks import ModelCheckpoint

from src import GLUEDataModule, GLUETransformer

EPOCHS = 3  # do not change this


def train_experiment(wandb_project: str, checkpoint_dir: str, **kwargs: dict):
    if "batch_size" in kwargs:
        kwargs["train_batch_size"] = kwargs["batch_size"]
        kwargs["eval_batch_size"] = kwargs["batch_size"]

    wandb.init(
        project=wandb_project,
        name=f"distilbert-base-uncased-{'-'.join('{}_{}'.format(key, val) for key, val in kwargs.items())}",
        config=kwargs,
        reinit="finish_previous",  # allows multiple runs in same script
    )
    logger = WandbLogger(project=wandb_project, save_dir=checkpoint_dir)  # use your experiment tracking tool's logger

    # Configure checkpoint saving
    # This saves the best model based on validation loss
    checkpoint_callback = ModelCheckpoint(
        dirpath=checkpoint_dir,
        filename='distilbert-mrpc-{epoch:02d}-{val_loss:.2f}',
        monitor='val_loss',
        mode='min',
        save_top_k=3,  # Keep best 3 checkpoints
        save_last=True,  # Also save the last checkpoint
        verbose=True
    )

    L.seed_everything(42)

    dm = GLUEDataModule(
        model_name_or_path="distilbert-base-uncased",
        task_name="mrpc",
        **kwargs
    )
    dm.setup("fit")
    model = GLUETransformer(
        model_name_or_path="distilbert-base-uncased",
        num_labels=dm.num_labels,
        eval_splits=dm.eval_splits,
        task_name=dm.task_name,
        **kwargs
    )

    trainer = L.Trainer(
        max_epochs=EPOCHS,
        accelerator="auto",
        devices=1,
        logger=logger,
        callbacks=[checkpoint_callback]  # Enable checkpoint saving
    )
    trainer.fit(model, datamodule=dm)

    wandb.finish()


if __name__ == "__main__":
    parser = argparse.ArgumentParser("python train.py")

    # Command line arguments for wandb
    parser.add_argument("--wandb-project", type=str, required=True, help="Name of Weights & Biases project")
    parser.add_argument("--checkpoint-dir", type=str, default='models', help="Directory to store checkpoints in")

    # Command line arguments for all supported hyperparameters
    parser.add_argument("-bs", "--batch-size", type=int, help="Training & evaluation batch size")
    parser.add_argument("-lr", "--learning-rate", type=float, help="Optimizer learning rate")
    parser.add_argument("-ws", "--warmup-steps", type=int, help="Number of warmup steps")
    parser.add_argument("-wd", "--weight-decay", type=float, help="Weight decay (L2 regularization)")
    parser.add_argument("-o", "--optimizer", choices=["AdamW", "Adam", "NAdam", "SGD"], help="Optimizer to use")
    parser.add_argument("-adm-b", "--adam-betas", type=lambda s: tuple(map(float, s.split(","))), help="Adam betas as 'beta1,beta2' (comma-separated)")
    parser.add_argument("-adm-e", "--adam-eps", type=float, help="Adam epsilon")
    parser.add_argument("-sgd-m", "--sgd-momentum", type=float, help="SGD momentum")
    parser.add_argument("-sgd-d", "--sgd-dampening", type=float, help="SGD dampening")
    parser.add_argument("-sgd-n", "--sgd-nesterov", action='store_true', help="Enable Nesterov momentum")

    args = parser.parse_args()
    args = {k: v for k, v in vars(args).items() if v}

    # Start the experiment
    train_experiment(**args)
